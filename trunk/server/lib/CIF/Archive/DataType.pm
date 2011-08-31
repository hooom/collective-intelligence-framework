package CIF::Archive::DataType;
use base 'CIF::DBI';

__PACKAGE__->columns(All => qw/id uuid/);
__PACKAGE__->columns(Primary => 'id');
__PACKAGE__->has_a(uuid => 'CIF::Archive');

use Module::Pluggable require => 1, except => qr/::Plugin::\S+::/;

# TODO -- re-eval
# this is a work-around for has_a wanting to map
# uuid => id
# __PACKAGE__->add_trigger(select  => \&remap_id);
#sub remap_id {
#    my $class = shift;
#    $class->{'uuid'} = CIF::Archive->retrieve(uuid => $class->uuid->id());
#}

sub prepare {
    my $class = shift;
    my $info = shift;

    my @bits = split(/::/,lc($class));
    my $t = $bits[$#bits];
    return(1) if($info->{'impact'} =~ /$t$/);
    return(0);
}

sub set_table {
    my $class = shift;

    my @bits = split(/::/,lc($class));
    my $t = $bits[$#bits];
    my $ptable = $class->table();
    if($bits[$#bits-1] ne 'plugin'){
        $t = $ptable.'_'.$bits[$#bits];
    }
    return($class->table($t));
}

sub _feed {
    my $class = shift;
    my $info = shift;

    my $key         = $info->{'key'};
    my $limit       = $info->{'limit'}          || 10000;
    my $restriction = $info->{'restriction'}    || 'private';
    my $severity    = $info->{'severity'}       || 'high';
    my $confidence  = $info->{'confidence'}     || 85;
    my $apikey     = $info->{'apikey'};

    require CIF::Utils;
    $apikey = CIF::Utils::genSourceUUID($apikey) unless(CIF::Utils::isUUID($apikey));

    my @bits = split(/::/,lc($class));
    my $feed_name = '';
    if($bits[$#bits-1] eq 'plugin'){
        $feed_name .= $bits[$#bits];
    } else {
        $feed_name .= $bits[$#bits].' '.$bits[$#bits-1];
    }
    my @recs;
    if($info->{'apikey'}){
        @recs = $class->search_feed(
            $info->{'detecttime'},
            $confidence,
            $severity,
            $restriction,
            $info->{'apikey'},
            $limit
        );
    } else {
        @recs = $class->search__feed(
            $info->{'detecttime'},
            $confidence,
            $severity,
            $restriction,
            $info->{'guid'},
            $limit
        );
    }
    return unless(@recs);
    if($recs[0]->{'data'}){
        my $hash;
        foreach (@recs){
            ## TODO -- test this
            unless($class->table() =~ /_whitelist/){
                next if($class->isWhitelisted($_->{$key},$apikey));
            }
            my $kk = $hash->{$_->{$key}};
            if($kk){
                next if($_->{'confidence'} <= $kk->{'confidence'});
            }
            $hash->{$_->{$key}} = $_;
        }
        @recs = map { $hash->{$_} } keys(%$hash);
        my @a;
        foreach(@recs){
            my $hh = JSON::from_json($_->{'data'});
            $hh->{'uuid'} = $_->uuid->id();
            push(@a,$hh);
        }
        @recs = @a;

        # sort it out
        @recs = sort { $a->{'detecttime'} cmp $b->{'detecttime'} } @recs;
    } else {
        my @array;
        foreach (@recs){
            my @keys = grep(!/^_/,keys %$_);
            my $h;
            foreach my $k (@keys){
                $h->{$k} = $_->{$k};
           }
            push(@array,$h);
        }
        @recs = @array;
    }
    my $feed = {
        feed    => {
            title   => $feed_name,
            entry   => \@recs,
        }
    };
    return($feed);
}

sub isWhitelisted { return; }

sub check_params {
    my ($self,$tests,$info) = @_;

    foreach my $key (keys %$info){
        if(exists($tests->{$key})){
            my $test = $tests->{$key};
            next unless($info->{$key});
            unless($info->{$key} =~ m/$test/){
                return(undef,'invaild value for '.$key.': '.$info->{$key});
            }
        }
    }
    return(1);
}

__PACKAGE__->set_sql('_feed' => qq{
    SELECT __ESSENTIAL__
    FROM __TABLE__
    WHERE 
        detecttime >= ?
        AND confidence >= ?
        AND severity >= ?
        AND restriction <= ?
        AND guid = ?
    ORDER BY severity desc, confidence desc, restriction desc, detecttime desc, id desc
    LIMIT ?
});

1;
