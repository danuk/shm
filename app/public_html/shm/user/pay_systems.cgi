#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

my $config = get_service("config");
my $list = $config->data_by_name(key => 'pay_systems')->{pay_systems};

my @ret;

for my $item ( keys %{ $list } ) {
    my $p = $list->{ $item };

    if ( $p->{ show_for_client } ) {
        if ( exists $p->{template_id} ) {
            if ( my $template = get_service('template', _id => $p->{template_id} ) ) {
                $p->{template} = $template->parsed();
            }
        }
        push @ret, $p;
    }
}

print_json( \@ret );

exit 0;
