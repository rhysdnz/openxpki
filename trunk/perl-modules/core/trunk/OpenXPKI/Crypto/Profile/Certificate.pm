# OpenXPKI::Crypto::Profile::Certificate.pm 
# Written 2005 by Michael Bell for the OpenXPKI project
# Copyright (C) 2005-2006 by The OpenXPKI Project
# $Revision$

use strict;
use warnings;

package OpenXPKI::Crypto::Profile::Certificate;

use base qw(OpenXPKI::Crypto::Profile::Base);

use OpenXPKI::Debug;
use OpenXPKI::Exception;
use OpenXPKI::DateTime;
use English;

use DateTime;
use Data::Dumper;
# use Smart::Comments;

sub new {
    my $that = shift;
    my $class = ref($that) || $that;

    my $self = {};

    bless $self, $class;

    my $keys = { @_ };
    $self->{config}    = $keys->{CONFIG}    if ($keys->{CONFIG});
    $self->{PKI_REALM} = $keys->{PKI_REALM} if ($keys->{PKI_REALM});
    $self->{TYPE}      = $keys->{TYPE}      if ($keys->{TYPE});
    $self->{CA}        = $keys->{CA}        if ($keys->{CA});
    $self->{ID}        = $keys->{ID}        if ($keys->{ID});
    $self->{CONFIG_ID} = $keys->{CONFIG_ID} if ($keys->{CONFIG_ID});

    if (not $self->{config})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_NEW_MISSING_XML_CONFIG");
    }

    if (! defined $self->{PKI_REALM})
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_NEW_MISSING_PKI_REALM");
    }

    if (! defined $self->{TYPE}
	|| (($self->{TYPE} ne 'ENDENTITY') 
	    && ($self->{TYPE} ne 'SELFSIGNEDCA'))) {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_NEW_INCORRECT_TYPE",
	    params => {
		TYPE      => $keys->{TYPE},
		PKI_REALM => $keys->{PKI_REALM},
		CA        => $keys->{CA},
		ID        => $keys->{ID},
	    },
	    );
    }

    if (! defined $self->{CA}) {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_NEW_MISSING_CA",
	    params => {
		TYPE      => $keys->{TYPE},
		PKI_REALM => $keys->{PKI_REALM},
		ID        => $keys->{ID},
	    },
	    );
    }


    if ($self->{TYPE} eq 'ENDENTITY') {
	if (! defined $self->{ID}) {
	    OpenXPKI::Exception->throw (
		message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_NEW_MISSING_ID");
	}
    }
    if ($self->{TYPE} eq 'SELFSIGNEDCA') {
	if (defined $self->{ID}) {
	    OpenXPKI::Exception->throw (
		message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_NEW_ID_SPECIFIED_FOR_SELFSIGNED_CA");
	}
    }


    ##! 2: "parameters ok"

    $self->load_profile($self->{CONFIG_ID});
    ##! 2: "config loaded"

    return $self;
}

sub load_profile
{
    my $self   = shift;
    my $cfg_id = shift;

    ## scan for correct pki realm and ca

    my %result    = $self->get_path($cfg_id);
    my $pki_realm = $result{PKI_REALM};

    ## scan for correct profile
 
    my @profile_path    = ("pki_realm", "common", "profiles");
    my @profile_counter = ($pki_realm, 0, 0);

    my $requested_id = $self->{ID};

    if ($self->{TYPE} eq "SELFSIGNEDCA")
    {
        push @profile_path, "selfsignedca";
        push @profile_counter, 0;

	$requested_id = $self->{CA};
    } else {
        push @profile_path, "endentity";
        push @profile_counter, 0;
    };

    push @profile_path, "profile";

    my $nr_of_profiles = $self->{config}->get_xpath_count(
            XPATH     => [@profile_path],
			COUNTER   => [@profile_counter],
            CONFIG_ID => $cfg_id,
    );
    my $found = 0;
  FINDPROFILE:
    for (my $ii = 0; $ii < $nr_of_profiles; $ii++)
    {
        if ($self->{config}->get_xpath(
            XPATH   => [@profile_path, "id"],
            COUNTER => [@profile_counter, $ii, 0],
            CONFIG_ID => $cfg_id)
            eq $requested_id)
        {
            push @profile_counter, $ii;
            $found = 1;
            last FINDPROFILE;
        }
    }
    
    if (! $found) {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_LOAD_PROFILE_UNDEFINED_PROFILE");
    }

    ## now we have a correct starting point to load the profile

    ## load general parameters


    $self->{PROFILE}->{DIGEST} = $self->{config}->get_xpath (
         XPATH     => [@profile_path, "digest"],
         COUNTER   => [@profile_counter, 0],
         CONFIG_ID => $cfg_id,
    );



    ###########################################################################
    # determine certificate validity

    my %entry_validity = $self->get_entry_validity(
	{
	    XPATH     => \@profile_path,
	    COUNTER   => \@profile_counter,
        CONFIG_ID => $cfg_id,
	});

    if (! exists $entry_validity{notafter}) {
	OpenXPKI::Exception->throw (
	    message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_LOAD_PROFILE_VALIDITY_NOTAFTER_NOT_DEFINED",
	    );
	
    }

    if (! exists $entry_validity{notbefore}) {
	# assign default (current timestamp) if notbefore is not specified
	$self->{PROFILE}->{NOTBEFORE} = DateTime->now( time_zone => 'UTC' );
    } else {
	$self->{PROFILE}->{NOTBEFORE} = OpenXPKI::DateTime::get_validity(
	    $entry_validity{notbefore});
    }

    # relative notafter is always relative to notbefore
    $entry_validity{notafter}->{REFERENCEDATE} = $self->{PROFILE}->{NOTBEFORE};
    $self->{PROFILE}->{NOTAFTER} = OpenXPKI::DateTime::get_validity(
        $entry_validity{notafter},
	);

    
    ## load extensions

    push @profile_path, "extensions";
    push @profile_counter, 0;

    foreach my $ext ("basic_constraints", "key_usage", "extended_key_usage",
                     "subject_key_identifier", "authority_key_identifier",
                     "issuer_alt_name", "crl_distribution_points", "authority_info_access",
                     "user_notice", "policy_identifier", "oid",
                     "netscape/comment", "netscape/certificate_type", "netscape/cdp")
    {
        $self->load_extension(
            PATH    => [@profile_path, $ext],
            COUNTER => [@profile_counter],
            CONFIG_ID => $cfg_id,
        );
    }

    ##! 2: Dumper($self->{PROFILE})
    ##! 1: "end"
    return 1;
}

sub get_notbefore
{
    my $self = shift;
    return $self->{PROFILE}->{NOTBEFORE}->clone();
}

sub get_notafter
{
    my $self = shift;
    return $self->{PROFILE}->{NOTAFTER}->clone();
}

sub get_digest
{
    my $self = shift;
    return $self->{PROFILE}->{DIGEST};
}

sub set_subject
{
    my $self = shift;
    $self->{PROFILE}->{SUBJECT} = shift;
    return 1;
}

sub get_subject
{
    my $self = shift;
    if (not exists $self->{PROFILE}->{SUBJECT} or
        length $self->{PROFILE}->{SUBJECT} == 0)
    {
        OpenXPKI::Exception->throw (
            message => "I18N_OPENXPKI_CRYPTO_PROFILE_CERTIFICATE_GET_SUBJECT_NOT_PRESENT");
    }
    return $self->{PROFILE}->{SUBJECT};
}

sub set_subject_alt_name {
    my $self = shift;
    my $subj_alt_name = shift;

    $self->set_extension(
        NAME     => 'subject_alt_name',
        CRITICAL => 'false', # TODO: is this correct?
        VALUES   => $subj_alt_name,
    );

    return 1;
}
1;
__END__

=head1 Name

OpenXPKI::Crypto::Profile::Certificate - cryptographic profile for certifcates.

