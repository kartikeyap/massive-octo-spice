package CIF::Rule;

use strict;
use warnings;

use Mouse;
use DateTime;
use Carp;
use Carp::Assert;
use CIF::Observable;
use CIF qw/$Logger parse_config normalize_timestamp is_url/;
use URI;
use URI::Escape;
use Data::Dumper;

use constant RE_IGNORE => qw(qr/[\.]$/);
use constant RE_SKIP => qr/remote|pattern|values|ignore/;

has [qw(store_content skip rule feed remote parser defaults disabled)] => (
    is      => 'ro',
);

has 'not_before'    => (
    is          => 'ro',
    isa         => 'CIF::Type::DateTimeInt',
    coerce      => 1,
    default     => sub { DateTime->today()->epoch() },
);

has '_now' => (
    is          => 'ro', 
    default     => sub { time() },
);

sub set_not_before {
    my $self = shift;
    my $arg = shift;
    
    $self->{'not_before'} = normalize_timestamp($arg)->epoch;
}

sub process {
    my $self = shift;
    my $args = shift;
    
    $self->_merge_defaults($args);
    $self->_normalize_otype($args->{'data'});
    $self->_normalize_ts($args->{'data'});
    return $args->{'data'};
}

sub _normalize_otype {
    my $self = shift;
    my $data = shift;

    if($self->defaults->{'otype'}){
        for($self->defaults->{'otype'}){
            if(/^url$/){
                $data->{'observable'} = _normalize_url($data->{'observable'});
            }
        }
    } else {
        $data->{'observable'} = _normalize_url($data->{'observable'});
    }
}

sub _normalize_url {
    my $data = shift;
    my $x = is_url($data);
    return $data unless($x);
    if ($x == 2){
        $data = 'http://'.$data;
    }
    $data = uri_escape_utf8($data,'\x00-\x1f\x7f-\xff');
    $data = URI->new($data)->canonical->as_string;
    return $data;
}

sub _normalize_ts {
    my $self = shift;
    my $data = shift;
    
    $data->{'reporttime'} = normalize_timestamp($data->{'reporttime'});
    $data->{'reporttime'} = $data->{'reporttime'}->ymd().'T'.$data->{'reporttime'}->hms().'Z';
    
    if($data->{'firsttime'}){
        $data->{'firsttime'} = normalize_timestamp($data->{'firsttime'});
        $data->{'firsttime'} = $data->{'firsttime'}->ymd().'T'.$data->{'firsttime'}->hms().'Z';
    }
    
    if($data->{'lasttime'}){
        $data->{'lasttime'} = normalize_timestamp($data->{'lasttime'});
        $data->{'lasttime'} = $data->{'lasttime'}->ymd().'T'.$data->{'lasttime'}->hms().'Z';
        $data->{'firsttime'} = $data->{'lasttime'} unless($data->{'firsttime'});
    }
    
    return $data;
}

sub _merge_defaults {
    my $self = shift;
    my $args = shift;

    return unless($self->defaults);
    foreach my $k (keys %{$self->defaults}){
        next if($k =~ RE_SKIP); 
        for($self->defaults->{$k}){
            if($_ && $_ =~ /<(\S+)>/){
                # if we have something that requires expansion
                # < >'s
                my $val;
                $val = $args->{'data'}->{$1} || $self->defaults->{$1};
                unless($val){
                    warn 'missing: '.$1;
                    assert($val);
                }
                
                # replace the 'variable'
                my $default = $_;
                $default =~ s/<\S+>/$val/;
                $args->{'data'}->{$k} = $default;
            } else {
                $args->{'data'}->{$k} = $self->defaults->{$k};
            }
        }
    }
}

sub ignore {
    my $self = shift;
    my $arg = shift;

    foreach (RE_IGNORE){
        return 1 if($arg =~ $_);
    }
}

__PACKAGE__->meta->make_immutable();

1;
