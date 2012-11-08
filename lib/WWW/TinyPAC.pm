package OpenILS::WWW::TinyPAC;
use base q/OpenILS::WWW::EGCatLoader/;
use strict; use warnings;
use Apache2::Const -compile => qw(OK);

sub load {
	my $self = shift;
	
	$self->init_ro_object_cache;
	my $stat = $self->load_common;
	return $stat unless $stat == Apache2::Const::OK;

	$self->ctx->{opac_root} =~ s/opac/tinypac/g;

	my $path = $self->apache->path_info;

	return $self->load_simple("home") if $path =~ m|tinypac/home|;
	return $self->load_rresults if $path =~ m|tinypac/results|;
	return $self->load_record if $path =~ m|tinypac/record|;

    return $self->load_logout if $path =~ m|tinypac/logout|;

    if($path =~ m|tinypac/login|) {
        return $self->load_login unless $self->editor->requestor; # already logged in?

        # This will be less confusing to users than to be shown a login form
        # when they're already logged in.
        return $self->generic_redirect(
            sprintf(
                "https://%s%s/myopac/main",
                $self->apache->hostname, $self->ctx->{opac_root}
            )
        );
    }

    return $self->redirect_auth unless $self->editor->requestor;

    return $self->load_logout if $path =~ m|tinypac/logout|;

    # Don't cache anything requiring auth for security reasons
    $self->apache->headers_out->add("cache-control" => "no-store, no-cache, must-revalidate");
    $self->apache->headers_out->add("expires" => "-1");

    return $self->load_email_record if $path =~ m|tinypac/record/email|;

    return $self->load_place_hold if $path =~ m|tinypac/place_hold|;
    return $self->load_myopac_holds if $path =~ m|tinypac/myopac/holds|;
    return $self->load_myopac_circs if $path =~ m|tinypac/myopac/circs|;
    return $self->load_myopac_main if $path =~ m|tinypac/myopac/main|;


	return Apache2::Const::OK;
}

1;
