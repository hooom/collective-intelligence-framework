package CIF::Archive::DataType::Plugin::Url::Phishing;
use base 'CIF::Archive::DataType::Plugin::Url';

sub prepare {
    my $class = shift;
    my $info = shift;
    return(0) unless($info->{'impact'} =~ /phish/);
    return('phishing');
}

1;

