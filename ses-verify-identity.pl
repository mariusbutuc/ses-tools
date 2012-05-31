#!/usr/bin/perl -w

# Copyright 2010 Amazon.com, Inc. or its affiliates. All Rights Reserved.
#
# Licensed under the Apache License, Version 2.0 (the "License"). You may not 
# use this file except in compliance with the License. A copy of the License 
# is located at
#
#        http://aws.amazon.com/apache2.0/
#
# or in the "LICENSE" file accompanying this file. This file is distributed 
# on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either 
# express or implied. See the License for the specific language governing 
# permissions and limitations under the License.

# This is a code sample showing how to use the Amazon Simple Email Service from the
# command line.  To learn more about this code sample, see the AWS Simple Email
# Service Developer Guide. 


use strict;
use warnings;
use Switch;
use Getopt::Long;
use Pod::Usage;
use XML::LibXML;
use SES;


my %opts = ();
my %params = ();


# Parse the command line arguments and place them in the %opts hash.
sub parse_args {
    GetOptions('verbose' => \$opts{'verbose'},
               'e=s'     => \$opts{'e'},
               'k=s'     => \$opts{'k'},
               'v=s'     => \$opts{'v'},
               'd=s'     => \$opts{'d'},
               'l'       => \$opts{'l'},
               'a=s'     => \$opts{'a'},
               'help'    => \$opts{'h'}) or pod2usage(-exitval => 2);
    pod2usage(-exitstatus => 0, -verbose => 2) if ($opts{'h'});
    $opts{'a'} = SES::parse_list($opts{'a'}, ',') if ($opts{'a'});
}


# Validate the arguments passed on the command line.
sub validate_opts {
    pod2usage(-exitval => 2) unless (
        defined($opts{'v'}) ^ defined($opts{'d'}) ^ defined($opts{'l'}) ^ defined($opts{'a'}));
}


# Determine the type of the identity (domain / email address)
sub get_identity_type {
    my $sender = shift;

    if ($sender =~ /^.*@.*$/) {
        return 'email';
    } else {
        return 'domain';
    }
}


# Prepare the parameters for the service call.
sub prepare_params {
    if ($opts{'v'}) {
        my $identity_type = get_identity_type($opts{'v'});
        switch ($identity_type) {
            case 'email' {
                $params{'EmailAddress'}          = $opts{'v'};
                $params{'Action'}                = 'VerifyEmailIdentity';
            }
            case 'domain' {
                $params{'Domain'}                = $opts{'v'};
                $params{'Action'}                = 'VerifyDomainIdentity';
            }
        }
    } elsif ($opts{'l'}) {
        $params{'Action'}                        = 'ListIdentities';
    } elsif ($opts{'d'}) {
        $params{'Identity'}                      = $opts{'d'};
        $params{'Action'}                        = 'DeleteIdentity';
    } elsif ($opts{'a'}) {
        my @opt_a = @{$opts{'a'}};
        for (my $i = 0; $i <= $#opt_a; $i++) {
            $params{'Identities.member.'.($i+1)} = $opt_a[$i];
        }
        $params{'Action'}                        = 'GetIdentityVerificationAttributes';
    }
}


# Prints the data returned by the service call.
sub print_response {
    my $response_content = shift;

    my $parser = XML::LibXML->new();
    my $dom = $parser->parse_string($response_content);
    my $xpath = XML::LibXML::XPathContext->new($dom);
    $xpath->registerNs('ns', $SES::aws_email_ns);

    if ($opts{'v'}) {
        my $identity_type = get_identity_type($opts{'v'});
        switch ($identity_type) {
            case 'email' {
            }
            case 'domain' {
                my $node = ${$xpath->findnodes('/ns:VerifyDomainIdentityResponse' .
                                               '/ns:VerifyDomainIdentityResult' .
                                               '/ns:VerificationToken')}[0];
                my $token = $node->textContent();
                print "$token\n";
            }
        }
    }

    if ($opts{'l'}) {
        my @nodes = $xpath->findnodes('/ns:ListIdentitiesResponse' .
                                      '/ns:ListIdentitiesResult' .
                                      '/ns:Identities' .
                                      '/ns:member');
        foreach my $node (@nodes) {
            my $token = $node->textContent();
            print "$token\n";
        }
    }

    if ($opts{'d'}) {
    }

    if ($opts{'a'}) {
        my @nodes = $xpath->findnodes('/ns:GetIdentityVerificationAttributesResponse' .
                                      '/ns:GetIdentityVerificationAttributesResult' .
                                      '/ns:VerificationAttributes' .
                                      '/ns:entry');
        print "Identity,Status,VerificationToken\n";
        foreach my $node (@nodes) {
            my $identity = ${$xpath->findnodes('ns:key', $node)}[0]->textContent();
            my $value    = ${$xpath->findnodes('ns:value', $node)}[0];
            my $status   = ${$xpath->findnodes('ns:VerificationStatus', $value)}[0]->textContent();
            my $token    = ${$xpath->findnodes('ns:VerificationToken', $value)}[0];
            $token = $token ? $token->textContent() : '';
            my $line     = join ',', ($identity, $status, $token);
            print "$line\n";
        }
    }
}


# Main sequence of steps required to make a successful service call.
parse_args;
validate_opts;
prepare_params;
my ($response_code, $response_content, $response_flag, $next_token);
do {
    ($response_code, $response_content, $response_flag, $next_token) = SES::call_ses \%params, \%opts;
    switch ($response_flag) {
        case /^THROTTLING/  { exit 75; }
    }
    switch ($response_code) {
        case '200' {              # OK
            print_response $response_content;
            if ($next_token) {
                $params{'NextToken'} = $next_token;
            } else {
                exit  0;
            }
        }
        case '400' { exit  1; }   # BAD_INPUT
        case '403' { exit 31; }   # SERVICE_ACCESS_ERROR
        case '500' { exit 32; }   # SERVICE_EXECUTION_ERROR
        case '503' { exit 30; }   # SERVICE_ERROR
        else       { exit -1; }
    }
} while ($next_token);


=head1 NAME

ses-verify-identity.pl - Verify identity to be used with the Amazon Simple Email Service (SES).

=head1 SYNOPSIS

B<ses-verify-identity.pl> [B<--help>] [B<-e> URL] [B<-k> FILE] [B<--verbose>] B<-v> IDENTITY | B<-l> | B<-d> IDENTITY | B<-a> IDENTITY

=head1 DESCRIPTION

B<ses-verify-identity.pl> Verifies, lists, deletes and retrieves verification attributes for identities.

=head1 OPTIONS

=over 8

=item B<--help>

Print the manual page.

=item B<-e> URL

The Amazon SES endpoint URL to use. If an endpoint is not provided then a default one will be used.
The default endpoint is "https://email.us-east-1.amazonaws.com/".

=item B<-k> FILE

The Amazon Web Services (AWS) credentials file to use. If the credentials
file is not provided the script will try to get the credentials file from the
B<AWS_CREDENTIALS_FILE> environment variable and if this fails then the script will fail
with an error message.

=item B<--verbose>

Be verbose and display detailed information about the endpoint response.

=item B<-v> IDENTITY

Verify identity. It can be either an email address or a domain.

=item B<-l>

List all identities.

=item B<-d> IDENTITY

Delete identity.

=item B<-a> IDENTITY

Retrieve verification attributes for an identity.

=back

=head1 COPYRIGHT

Amazon.com, Inc. or its affiliates

=cut
