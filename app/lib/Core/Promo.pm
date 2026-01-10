package Core::Promo;

use v5.14;
use parent 'Core::Base';
use Core::Base;
use Core::Utils qw(
    now
    passgen
    print_json
);

sub table { return 'promo_codes' };

sub structure {
    return {
        id => {
            type => 'text',
            key => 1,
            title => 'id промокода',
        },
        template_id => {
            type => 'text',
            title => 'id шаблона',
        },
        user_id => {
            type => 'number',
            # key => 1,
            title => 'id пользователя кто создал',
        },
        created => {
            type => 'now',
            title => 'дата создания',
        },
        used => {
            type => 'date',
            title => 'дата использования',
        },
        used_by => {
            type => 'number',
            title => 'id пользователя кто использовал промокод',
        },
        settings => {
            type => 'json',
            value => {},
        },
        expire => {
            type => 'date',
            title => 'дата истечения',
        },
    }
}

sub table_allow_insert_key { return 1 };

# В БД может быть несколько кодов с одинаковыми ID.
# Всегда возвращаем первый (корневой)
sub get {
    my $self = shift;

    my @data = $self->_list(
        where => {
            id => $self->id,
        },
        order => [ 'created' => 'asc' ],
        limit => 1,
    );

    $self->{res} = $data[0];
    return wantarray ? %{ $self->{res} } : $self->{res};
}

# Используем второе ключевое поле (`user_id`)
sub add {
    my $self = shift;
    return $self->SUPER::add( @_, user_id => $self->user_id );
}

sub _set {
    my $self = shift;
    return $self->SUPER::_set(
        @_,
        where => { id => $self->id, user_id => $self->promo_user_id },
     );
}

sub user_id {
    my $self = shift;
    return $self->{user_id};
}

sub promo_user_id {
    my $self = shift;
    return $self->res->{user_id};
}

sub generate {
    my $self = shift;
    my %args = (
        reusable => 0,
        code => undef,
        template_id => undef,
        expire => undef,
        settings => {
            count => 1,
            length => 10,
            prefix => '',
            quantity => 1,
            reusable => 0,
            status => 1,
        },
        get_smart_args( @_ ),
    );

    $args{settings}{count} = $args{count} if $args{count};
    $args{settings}{length} = $args{length} if $args{length};
    $args{settings}{prefix} = $args{prefix} if $args{prefix};
    $args{settings}{quantity} = $args{quantity} if $args{quantity};
    $args{settings}{reusable} //= exists $args{reusable} ? $args{reusable} : 0;
    $args{settings}{status} //= exists $args{status} ? $args{status} : 1;

    unless ( $args{template_id} ) {
        report->warning( 'template_id required' );
        return [];
    }

    my $expire = $args{expire};
    $expire =~s/\..+$//;

    my %settings = %{ $args{settings} || {} };

    my @codes;
    if ( $settings{reusable} ) {
        my $id = $settings{prefix} . uc( passgen( $settings{length} || 10 ) );
        my $code = $self->add(
            id => $args{code} || $id,
            template_id => $args{template_id},
            settings => \%settings,
            expire => $expire,
        );
        push @codes, $code;
    } else {
        for ( 1 .. $settings{count} ) {
            my $id = $settings{prefix} . uc( passgen( $settings{length} || 10 ) );
            my $code = $self->add(
                id => $id,
                template_id => $args{template_id},
                settings => \%settings,
                expire => $expire,
            );
            push @codes, $code;
        }
    }
    return \@codes;
}

sub is_used {
    my $self = shift;
    return $self->get_used_by;
}

sub status { shift->settings->{status} };

sub api_get {
    my $self = shift;

    my @list = $self->list(
        where => {
            user_id => $self->user->id,
            used_by => $self->user->id,
        },
    );

    my @data;
    foreach my $item (@list) {
        if (ref($item) eq 'HASH') {
            push @data, {
                promo_code => $item->{id},
                used_date => $item->{used},
            };
        }
    }

    return @data;
}

sub api_apply {
    my $self = shift;
    my %args = (
        code => undef,
        @_,
    );

    if ( $self->apply( $args{code} ) ) {
        print_json( { used => "true" } );
    }
    return;
}

sub apply {
    my $self = shift;
    my $code = shift;

    my $subscription = get_service('Cloud::Subscription');
    unless ($subscription->check_subscription()) {
        report->status(403);
        report->error( "Требуется активация подписки" );
        return;
    }

    $self = $self->id( $code ) if $code;

    unless ( $self && $self->get ) {
        report->warning( sprintf("promo code `%s` not found", $code ) );
        return;
    }

    my $settings = $self->get_settings;

    if ( exists $settings->{status} && $settings->{status} == 0 ) {
        report->warning( sprintf("promo code `%s` is inactive", $self->id ) );
        return;
    }

    if ( $self->get_expire && $self->get_expire lt now ) {
        report->warning( sprintf("promo code `%s` has expired", $self->id ) );
        return;
    }

    if ( $settings->{reusable} && exists $settings->{quantity} && $settings->{quantity} == 0 ) {
        report->warning( sprintf("promo code `%s` has no remaining uses", $self->id ) );
        return;
    }

    if ( $self->get_used ) {
        report->warning( sprintf("promo code `%s` has already been used", $self->id ) );
        return;
    }

    my $template = $self->srv('template')->id( $self->get_template_id );
    unless ( $template ) {
        report->warning( sprintf("template `%s` not exists", $self->get_template_id ) );
        return undef;
    }

    if ( $settings->{reusable} ) {
        # Создаем новый объект
        use Clone 'clone';
        my $reusable_promo = clone $self;

        my $id = $reusable_promo->add(
            id => $self->id,
            template_id => $self->get_template_id,
            user_id => $self->user_id,
            used_by => $self->user_id,
            used => now,
            settings => $settings,
        );

        unless ( $id ) {
            report->warning( sprintf("promo code `%s` has already been used by this user", $self->id ) );
            return;
        }
        $self->set_settings( { quantity => $settings->{quantity} - 1 } ) if $settings->{quantity};
    } else {
        $self->set( used_by => $self->user_id, used => now );
    }

    return $template->parse(
        event_name => 'PROMO',
        vars => {
            promo => $self,
        },
    ) || 'success';
}

sub update {
    my $self = shift;
    my %args = (
        id => undef,
        template_id => undef,
        settings => undef,
        expire => undef,
        @_,
    );

    unless ( $args{id} || $args{user_id} ) {
        report->warning('id required');
        return [];
    }

    my $promo = first_item $self->items(
        where => {
            id => $args{id},
            user_id => $self->user_id,
        },
    );
    unless ( $promo ) {
        report->warning('promocode not found');
        return [];
    }

    $args{expire} =~s/\..+$// if $args{expire};

    $args{where} = {
        id => $args{id},
        user_id => $self->user_id,
    };

    $promo->set( %args );

    return scalar $self->get;
}

sub delete {
    my $self = shift;
    my %args = (
        id => $self->id,
        @_,
    );

    unless ( $args{id} || $args{user_id} ) {
        report->warning('id required');
        return;
    }

    $args{where} = {
        id => $args{id},
        user_id => $self->user_id,
    };

    return $self->SUPER::delete( %args );
}

1;