package Core::Transport::Local;

use parent 'Core::Base';

use v5.14;
use utf8;
use Core::Base;
use Core::Const;

sub send {
    my $self = shift;
    my $task = shift;

    my $template_id =   $task->event_settings->{template_id} ||
                        $task->settings->{template_id};

    unless ( $template_id ) {
        if ( my $server = $task->server ) {
            $template_id = $server->get_settings->{template_id};
        }
    }

    my $template = get_service('template', _id => $template_id );
    unless ( $template ) {
        return undef, {
            error => "template with id `$template_id` not found",
        }
    }

    my %settings = (
        %{ $template->get_settings || {} },
        %{ $task->event_settings },
    );

    my $content = $template->parse(
        $task->settings->{user_service_id} ? ( usi => $task->settings->{user_service_id} ) : (),
        task => $task,
        vars => {
            SUCCESS => SUCCESS,
            FAIL => FAIL,
            STUCK => '',
        },
    );

    my $status = SUCCESS;
    my %answer = $task->answer;
    if ( exists $answer{status} ) {
        $status = length $answer{status} ? $answer{status} : undef;
    }

    return $status, {
        result => $content,
        %answer,
    };
}

1;
