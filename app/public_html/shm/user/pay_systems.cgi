#!/usr/bin/perl

use v5.14;

use SHM qw(:all);
my $user = SHM->new();

my $config = $user->srv("config", _id => 'pay_systems');
my $list = $config ? $config->get_data : {};

my @ret;

for my $item ( keys %{ $list } ) {
    my $p = $list->{ $item };

    if ( $p->{ show_for_client } ) {
        if ( exists $p->{template_id} ) {
            if ( my $template = $user->srv('template', _id => $p->{template_id} ) ) {
                $p->{template} = $template->parse();
            }
        }
        push @ret, $p;
    }
}

print_json( \@ret );

exit 0;
