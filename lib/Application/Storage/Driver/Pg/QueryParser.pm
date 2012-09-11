use strict;
use warnings;

package OpenILS::Application::Storage::Driver::Pg::QueryParser;
use OpenILS::Application::Storage::QueryParser;
use base 'QueryParser';
use OpenSRF::Utils::JSON;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor;
use Switch;
my $U = 'OpenILS::Application::AppUtils';

my ${spc} = ' ' x 2;
sub subquery_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    return sprintf(' ((%s)) ',
        join(
            ') || (',
            map {
                $_->query_text
            } @{
                OpenILS::Utils::CStoreEditor
                    ->new
                    ->search_actor_search_query({ id => $params })
            }
        )
    );
}

sub filter_group_entry_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    return sprintf(' saved_query(%s)', 
        join(
            ',', 
            map {
                $_->query
            } @{
                OpenILS::Utils::CStoreEditor
                    ->new
                    ->search_actor_search_filter_group_entry({ id => $params })
            }
        )
    );
}

sub location_groups_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    return sprintf(' %slocations(%s)',
        $negate ? '-' : '',
        join(
            ',',
            map {
                $_->location
            } @{
                OpenILS::Utils::CStoreEditor
                    ->new
                    ->search_asset_copy_location_group_map({ lgroup => $params })
            }
        )
    );
}

sub format_callback {
    my ($invocant, $self, $struct, $filter, $params, $negate) = @_;

    my $return = '';
    my $negate_flag = ($negate ? '-' : '');
    if(@$params[0]) {
        my ($t,$f) = split('-', @$params[0]);
        $return .= $negate_flag .'item_type(' . join(',',split('', $t)) . ')' if ($t);
        $return .= ' ' if ($t and $f);
        $return .= $negate_flag .'item_form(' . join(',',split('', $f)) . ')' if ($f);
        $return = '(' . $return . ')' if ($t and $f);
    }
    return $return;
}

sub quote_value {
    my $self = shift;
    my $value = shift;

    if ($value =~ /^\d/) { # may have to use non-$ quoting
        $value =~ s/'/''/g;
        $value =~ s/\\/\\\\/g;
        return "E'$value'";
    }
    return "\$_$$\$$value\$_$$\$";
}

sub quote_phrase_value {
    my $self = shift;
    my $value = shift;

    my $left_anchored  = $value =~ m/^\^/;
    my $right_anchored = $value =~ m/\$$/;
    $value =~ s/\^//   if $left_anchored;
    $value =~ s/\$$//  if $right_anchored;
    $value = quotemeta($value);
    $value = '^' . $value if $left_anchored;
    $value = "$value\$"   if $right_anchored;
    return $self->quote_value($value);
}

sub init {
    my $class = shift;
}

sub default_preferred_language {
    my $self = shift;
    my $lang = shift;

    $self->custom_data->{default_preferred_language} = $lang if ($lang);
    return $self->custom_data->{default_preferred_language};
}

sub default_preferred_language_multiplier {
    my $self = shift;
    my $lang = shift;

    $self->custom_data->{default_preferred_language_multiplier} = $lang if ($lang);
    return $self->custom_data->{default_preferred_language_multiplier};
}

sub simple_plan {
    my $self = shift;

    return 0 unless $self->parse_tree;
    return 0 if @{$self->parse_tree->filters};
    return 0 if @{$self->parse_tree->modifiers};
    for my $node ( @{ $self->parse_tree->query_nodes } ) {
        return 0 if (!ref($node) && $node eq '|');
        next unless (ref($node));
        return 0 if ($node->isa('QueryParser::query_plan'));
    }

    return 1;
}

sub toSQL {
    my $self = shift;
    return $self->parse_tree->toSQL;
}

sub dynamic_filters {
    my $self = shift;
    my $new = shift;

    $self->custom_data->{dynamic_filters} ||= [];
    push(@{$self->custom_data->{dynamic_filters}}, $new) if ($new);
    return $self->custom_data->{dynamic_filters};
}

sub dynamic_sorters {
    my $self = shift;
    my $new = shift;

    $self->custom_data->{dynamic_sorters} ||= [];
    push(@{$self->custom_data->{dynamic_sorters}}, $new) if ($new);
    return $self->custom_data->{dynamic_sorters};
}

sub facet_field_id_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{facet_field_id_map} ||= {};
    $self->custom_data->{facet_field_id_map} = $map if ($map);
    return $self->custom_data->{facet_field_id_map};
}

sub add_facet_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;

    $self->add_facet_field( $class => $field );
    $self->facet_field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->facet_field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub facet_field_class_by_id {
    my $self = shift;
    my $id = shift;

    return $self->facet_field_id_map->{by_id}{$id};
}

sub facet_field_ids_by_class {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return undef unless ($class);

    if ($field) {
        return [$self->facet_field_id_map->{by_class}{$class}{$field}];
    }

    return [values( %{ $self->facet_field_id_map->{by_class}{$class} } )];
}

sub search_field_id_map {
    my $self = shift;
    my $map = shift;

    $self->custom_data->{search_field_id_map} ||= {};
    $self->custom_data->{search_field_id_map} = $map if ($map);
    return $self->custom_data->{search_field_id_map};
}

sub add_search_field_id_map {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $id = shift;
    my $weight = shift;

    $self->add_search_field( $class => $field );
    $self->search_field_id_map->{by_id}{$id} = { classname => $class, field => $field, weight => $weight };
    $self->search_field_id_map->{by_class}{$class}{$field} = $id;

    return {
        by_id => { $id => { classname => $class, field => $field, weight => $weight } },
        by_class => { $class => { $field => $id } }
    };
}

sub search_field_class_by_id {
    my $self = shift;
    my $id = shift;

    return $self->search_field_id_map->{by_id}{$id};
}

sub search_field_ids_by_class {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return undef unless ($class);

    if ($field) {
        return [$self->search_field_id_map->{by_class}{$class}{$field}];
    }

    return [values( %{ $self->search_field_id_map->{by_class}{$class} } )];
}

sub relevance_bumps {
    my $self = shift;
    my $bumps = shift;

    $self->custom_data->{rel_bumps} ||= {};
    $self->custom_data->{rel_bumps} = $bumps if ($bumps);
    return $self->custom_data->{rel_bumps};
}

sub find_relevance_bumps {
    my $self = shift;
    my $class = shift;
    my $field = shift;

    return $self->relevance_bumps->{$class}{$field};
}

sub add_relevance_bump {
    my $self = shift;
    my $class = shift;
    my $field = shift;
    my $type = shift;
    my $multiplier = shift;
    my $active = shift;

    if (defined($active) and $active eq 'f') {
        $active = 0;
    } else {
        $active = 1;
    }

    $self->relevance_bumps->{$class}{$field}{$type} = { multiplier => $multiplier, active => $active };

    return { $class => { $field => { $type => { multiplier => $multiplier, active => $active } } } };
}


sub initialize_search_field_id_map {
    my $self = shift;
    my $cmf_list = shift;

    for my $cmf (@$cmf_list) {
        __PACKAGE__->add_search_field_id_map( $cmf->field_class, $cmf->name, $cmf->id, $cmf->weight ) if ($U->is_true($cmf->search_field));
        __PACKAGE__->add_facet_field_id_map( $cmf->field_class, $cmf->name, $cmf->id, $cmf->weight ) if ($U->is_true($cmf->facet_field));
    }

    return $self->search_field_id_map;
}

sub initialize_aliases {
    my $self = shift;
    my $cmsa_list = shift;

    for my $cmsa (@$cmsa_list) {
        if (!$cmsa->field) {
            __PACKAGE__->add_search_class_alias( $cmsa->field_class, $cmsa->alias );
        } else {
            my $c = $self->search_field_class_by_id( $cmsa->field );
            __PACKAGE__->add_search_field_alias( $cmsa->field_class, $c->{field}, $cmsa->alias );
        }
    }
}

sub initialize_relevance_bumps {
    my $self = shift;
    my $sra_list = shift;

    for my $sra (@$sra_list) {
        my $c = $self->search_field_class_by_id( $sra->field );
        __PACKAGE__->add_relevance_bump( $c->{classname}, $c->{field}, $sra->bump_type, $sra->multiplier, $sra->active );
    }

    return $self->relevance_bumps;
}

sub initialize_query_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.metabib_field_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "cmfinm" : ["norm"] }, "order_by" : [{ "class" : "cmfinm", "field" : "pos" }] }

    for my $cmfinm ( @$tree ) {
        my $field_info = $self->search_field_class_by_id( $cmfinm->field );
        __PACKAGE__->add_query_normalizer( $field_info->{classname}, $field_info->{field}, $cmfinm->norm->func, OpenSRF::Utils::JSON->JSON2perl($cmfinm->params) );
    }
}

sub initialize_dynamic_filters {
    my $self = shift;
    my $list = shift; # open-ils.cstore.direct.config.record_attr_definition.search.atomic { "id" : { "!=" : null } }

    for my $crad ( @$list ) {
        __PACKAGE__->dynamic_filters( __PACKAGE__->add_search_filter( $crad->name ) ) if ($U->is_true($crad->filter));
        __PACKAGE__->dynamic_sorters( $crad->name ) if ($U->is_true($crad->sorter));
    }
}

sub initialize_filter_normalizers {
    my $self = shift;
    my $tree = shift; # open-ils.cstore.direct.config.record_attr_index_norm_map.search.atomic { "id" : { "!=" : null } }, { "flesh" : 1, "flesh_fields" : { "crainm" : ["norm"] }, "order_by" : [{ "class" : "crainm", "field" : "pos" }] }

    for my $crainm ( @$tree ) {
        __PACKAGE__->add_filter_normalizer( $crainm->attr, $crainm->norm->func, OpenSRF::Utils::JSON->JSON2perl($crainm->params) );
    }
}

our $_complete = 0;
sub initialization_complete {
    return $_complete;
}

sub initialize {
    my $self = shift;
    my %args = @_;

    return $_complete if ($_complete);

    # tsearch rank normalization adjustments. see http://www.postgresql.org/docs/9.0/interactive/textsearch-controls.html#TEXTSEARCH-RANKING for details
    $self->custom_data->{rank_cd_weight_map} = {
        CD_logDocumentLength    => 1,
        CD_documentLength       => 2,
        CD_meanHarmonic         => 4,
        CD_uniqueWords          => 8,
        CD_logUniqueWords       => 16,
        CD_selfPlusOne          => 32
    };

    $self->add_search_modifier( $_ ) for (keys %{ $self->custom_data->{rank_cd_weight_map} });

    $self->initialize_search_field_id_map( $args{config_metabib_field} )
        if ($args{config_metabib_field});

    $self->initialize_aliases( $args{config_metabib_search_alias} )
        if ($args{config_metabib_search_alias});

    $self->initialize_relevance_bumps( $args{search_relevance_adjustment} )
        if ($args{search_relevance_adjustment});

    $self->initialize_query_normalizers( $args{config_metabib_field_index_norm_map} )
        if ($args{config_metabib_field_index_norm_map});

    $self->initialize_dynamic_filters( $args{config_record_attr_definition} )
        if ($args{config_record_attr_definition});

    $self->initialize_filter_normalizers( $args{config_record_attr_index_norm_map} )
        if ($args{config_record_attr_index_norm_map});

    $_complete = 1 if (
        $args{config_metabib_field_index_norm_map} &&
        $args{search_relevance_adjustment} &&
        $args{config_metabib_search_alias} &&
        $args{config_metabib_field} &&
        $args{config_record_attr_definition}
    );

    return $_complete;
}

sub TEST_SETUP {
    
    __PACKAGE__->add_search_field_id_map( series => seriestitle => 1 => 1 );

    __PACKAGE__->add_search_field_id_map( series => seriestitle => 1 => 1 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( series => seriestitle => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => abbreviated => 2 => 1 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => abbreviated => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => translated => 3 => 1 );
    __PACKAGE__->add_relevance_bump( title => translated => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => translated => full_match => 20 );
    
    __PACKAGE__->add_search_field_id_map( title => proper => 6 => 1 );
    __PACKAGE__->add_query_normalizer( title => proper => 'search_normalize' );
    __PACKAGE__->add_relevance_bump( title => proper => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( title => proper => full_match => 20 );
    __PACKAGE__->add_relevance_bump( title => proper => word_order => 10 );
    
    __PACKAGE__->add_search_field_id_map( author => corporate => 7 => 1 );
    __PACKAGE__->add_relevance_bump( author => corporate => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => corporate => full_match => 20 );
    
    __PACKAGE__->add_facet_field_id_map( author => personal => 8 => 1 );

    __PACKAGE__->add_search_field_id_map( author => personal => 8 => 1 );
    __PACKAGE__->add_relevance_bump( author => personal => first_word => 1.5 );
    __PACKAGE__->add_relevance_bump( author => personal => full_match => 20 );
    __PACKAGE__->add_query_normalizer( author => personal => 'search_normalize' );
    __PACKAGE__->add_query_normalizer( author => personal => 'split_date_range' );
    
    __PACKAGE__->add_facet_field_id_map( subject => topic => 14 => 1 );

    __PACKAGE__->add_search_field_id_map( subject => topic => 14 => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => topic => full_match => 1 );
    
    __PACKAGE__->add_search_field_id_map( subject => complete => 16 => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => first_word => 1 );
    __PACKAGE__->add_relevance_bump( subject => complete => full_match => 1 );
    
    __PACKAGE__->add_search_field_id_map( keyword => keyword => 15 => 1 );
    __PACKAGE__->add_relevance_bump( keyword => keyword => first_word => 1 );
    __PACKAGE__->add_relevance_bump( keyword => keyword => full_match => 1 );
    
    
    __PACKAGE__->add_search_class_alias( keyword => 'kw' );
    __PACKAGE__->add_search_class_alias( title => 'ti' );
    __PACKAGE__->add_search_class_alias( author => 'au' );
    __PACKAGE__->add_search_class_alias( author => 'name' );
    __PACKAGE__->add_search_class_alias( author => 'dc.contributor' );
    __PACKAGE__->add_search_class_alias( subject => 'su' );
    __PACKAGE__->add_search_class_alias( subject => 'bib.subject(?:Title|Place|Occupation)' );
    __PACKAGE__->add_search_class_alias( series => 'se' );
    __PACKAGE__->add_search_class_alias( keyword => 'dc.identifier' );
    
    __PACKAGE__->add_query_normalizer( author => corporate => 'search_normalize' );
    __PACKAGE__->add_query_normalizer( keyword => keyword => 'search_normalize' );
    
    __PACKAGE__->add_search_field_alias( subject => name => 'bib.subjectName' );
    
}

__PACKAGE__->default_search_class( 'keyword' );

# implements EG-specific stored subqueries
__PACKAGE__->add_search_filter( 'saved_query', sub { return __PACKAGE__->subquery_callback(@_) } );
__PACKAGE__->add_search_filter( 'filter_group_entry', sub { return __PACKAGE__->filter_group_entry_callback(@_) } );

# will be retained simply for back-compat
__PACKAGE__->add_search_filter( 'format', sub { return __PACKAGE__->format_callback(@_) } );

# grumble grumble, special cases against date1 and date2
__PACKAGE__->add_search_filter( 'before' );
__PACKAGE__->add_search_filter( 'after' );
__PACKAGE__->add_search_filter( 'between' );
__PACKAGE__->add_search_filter( 'during' );

# various filters for limiting in various ways
__PACKAGE__->add_search_filter( 'statuses' );
__PACKAGE__->add_search_filter( 'locations' );
__PACKAGE__->add_search_filter( 'location_groups', sub { return __PACKAGE__->location_groups_callback(@_) } );
__PACKAGE__->add_search_filter( 'bib_source' );
__PACKAGE__->add_search_filter( 'site' );
__PACKAGE__->add_search_filter( 'pref_ou' );
__PACKAGE__->add_search_filter( 'lasso' );
__PACKAGE__->add_search_filter( 'my_lasso' );
__PACKAGE__->add_search_filter( 'depth' );
__PACKAGE__->add_search_filter( 'language' );
__PACKAGE__->add_search_filter( 'offset' );
__PACKAGE__->add_search_filter( 'limit' );
__PACKAGE__->add_search_filter( 'check_limit' );
__PACKAGE__->add_search_filter( 'skip_check' );
__PACKAGE__->add_search_filter( 'superpage' );
__PACKAGE__->add_search_filter( 'superpage_size' );
__PACKAGE__->add_search_filter( 'estimation_strategy' );
__PACKAGE__->add_search_modifier( 'available' );
__PACKAGE__->add_search_modifier( 'staff' );

# Start from container data (bre, acn, acp): container(bre,bookbag,123,deadb33fdeadb33fdeadb33fdeadb33f)
__PACKAGE__->add_search_filter( 'container' );

# Start from a list of record ids, either bre or metarecords, depending on the #metabib modifier
__PACKAGE__->add_search_filter( 'record_list' );

# used internally, but generally not user-settable
__PACKAGE__->add_search_filter( 'preferred_language' );
__PACKAGE__->add_search_filter( 'preferred_language_weight' );
__PACKAGE__->add_search_filter( 'preferred_language_multiplier' );
__PACKAGE__->add_search_filter( 'core_limit' );

# XXX Valid values to be supplied by SVF
__PACKAGE__->add_search_filter( 'sort' );

# modifies core query, not configurable
__PACKAGE__->add_search_modifier( 'descending' );
__PACKAGE__->add_search_modifier( 'ascending' );
__PACKAGE__->add_search_modifier( 'nullsfirst' );
__PACKAGE__->add_search_modifier( 'nullslast' );
__PACKAGE__->add_search_modifier( 'metarecord' );
__PACKAGE__->add_search_modifier( 'metabib' );


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan;
use base 'QueryParser::query_plan';
use OpenSRF::Utils::Logger qw($logger);
use Data::Dumper;
use OpenILS::Application::AppUtils;
use OpenILS::Utils::CStoreEditor;
my $apputils = "OpenILS::Application::AppUtils";
my $editor = OpenILS::Utils::CStoreEditor->new;

sub toSQL {
    my $self = shift;

    my %filters;

    for my $f ( qw/preferred_language preferred_language_multiplier preferred_language_weight core_limit check_limit skip_check superpage superpage_size/ ) {
        my $col = $f;
        $col = 'preferred_language_multiplier' if ($f eq 'preferred_language_weight');
        my ($filter) = $self->find_filter($f);
        if ($filter and @{$filter->args}) {
            $filters{$col} = $filter->args->[0];
        }
    }
    $self->new_filter( statuses => [0,7,12] ) if ($self->find_modifier('available'));

    $self->QueryParser->superpage($filters{superpage}) if ($filters{superpage});
    $self->QueryParser->superpage_size($filters{superpage_size}) if ($filters{superpage_size});
    $self->QueryParser->core_limit($filters{core_limit}) if ($filters{core_limit});

    $logger->debug("Query plan:\n".Dumper($self));

    my $flat_plan = $self->flatten;

    # generate the relevance ranking
    my $rel = '1'; # Default to something simple in case rank_list is empty.
    $rel = "AVG(\n${spc}${spc}${spc}${spc}${spc}(" . join(")\n${spc}${spc}${spc}${spc}${spc}+ (", @{$$flat_plan{rank_list}}) . ")\n${spc}${spc}${spc}${spc})+1" if (@{$$flat_plan{rank_list}});

    # find any supplied sort option
    my ($sort_filter) = $self->find_filter('sort');
    if ($sort_filter) {
        $sort_filter = $sort_filter->args->[0];
    } else {
        $sort_filter = 'rel';
    }

    if (($filters{preferred_language} || $self->QueryParser->default_preferred_language) && ($filters{preferred_language_multiplier} || $self->QueryParser->default_preferred_language_multiplier)) {
        my $pl = $self->QueryParser->quote_value( $filters{preferred_language} ? $filters{preferred_language} : $self->QueryParser->default_preferred_language );
        my $plw = $filters{preferred_language_multiplier} ? $filters{preferred_language_multiplier} : $self->QueryParser->default_preferred_language_multiplier;
        $rel = "($rel * COALESCE( NULLIF( FIRST(mrd.attrs \@> hstore('item_lang', $pl)), FALSE )::INT * $plw, 1))";
    }
    $rel = "1.0/($rel)::NUMERIC";

    my $rank = $rel;

    my $desc = 'ASC';
    $desc = 'DESC' if ($self->find_modifier('descending'));

    my $nullpos = 'NULLS LAST';
    $nullpos = 'NULLS FIRST' if ($self->find_modifier('nullsfirst'));

    if (grep {$_ eq $sort_filter} @{$self->QueryParser->dynamic_sorters}) {
        $rank = "FIRST(mrd.attrs->'$sort_filter')"
    } elsif ($sort_filter eq 'create_date') {
        $rank = "FIRST((SELECT create_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
    } elsif ($sort_filter eq 'edit_date') {
        $rank = "FIRST((SELECT edit_date FROM biblio.record_entry rbr WHERE rbr.id = m.source))";
    } else {
        # default to rel ranking
        $rank = $rel;
    }

    my $key = 'm.source';
    $key = 'm.metarecord' if (grep {$_->name eq 'metarecord' or $_->name eq 'metabib'} @{$self->modifiers});

    my $core_limit = $self->QueryParser->core_limit || 25000;

    my $flat_where = $$flat_plan{where};
    if ($flat_where eq '()') {
        $flat_where = '';
    } else {
        $flat_where = "AND $flat_where";
    }

    my $site = $self->find_filter('site');
    if ($site && $site->args) {
        $site = $site->args->[0];
        if ($site && $site !~ /^(-)?\d+$/) {
            my $search = $editor->search_actor_org_unit({ shortname => $site });
            $site = @$search[0]->id if($search && @$search);
            $site = undef unless ($search);
        }
    } else {
        $site = undef;
    }
    my $lasso = $self->find_filter('lasso');
    if ($lasso && $lasso->args) {
        $lasso = $lasso->args->[0];
        if ($lasso && $lasso !~ /^\d+$/) {
            my $search = $editor->search_actor_org_lasso({ name => $lasso });
            $lasso = @$search[0]->id if($search && @$search);
            $lasso = undef unless ($search);
        }
    } else {
        $lasso = undef;
    }
    my $depth = $self->find_filter('depth');
    if ($depth && $depth->args) {
        $depth = $depth->args->[0];
        if ($depth && $depth !~ /^\d+$/) {
            # This *is* what metabib.pm has been doing....but it makes no sense to me. :/
            # Should this be looking up the depth of the OU type on the OU in question?
            my $search = $editor->search_actor_org_unit([{ name => $depth },{ opac_label => $depth }]);
            $depth = @$search[0]->id if($search && @$search);
            $depth = undef unless($search);
        }
    } else {
        $depth = undef;
    }
    my $pref_ou = $self->find_filter('pref_ou');
    if ($pref_ou && $pref_ou->args) {
        $pref_ou = $pref_ou->args->[0];
        if ($pref_ou && $pref_ou !~ /^(-)?\d+$/) {
            my $search = $editor->search_actor_org_unit({ shortname => $pref_ou });
            $pref_ou = @$search[0]->id if($search && @$search);
            $pref_ou = undef unless ($search);
        }
    } else {
        $pref_ou = undef;
    }

    # Supposedly at some point a site of 0 and a depth will equal user lasso id.
    # We need OU buckets before that happens. 'my_lasso' is, I believe, the target filter for it.

    $site = -$lasso if ($lasso);

    # Default to the top of the org tree if we have nothing else. This would need tweaking for the user lasso bit.
    if (!$site) {
        my $search = $editor->search_actor_org_unit({ parent_ou => undef });
        $site = @$search[0]->id if ($search);
    }

    my $depth_check = '';
    $depth_check = ", $depth" if ($depth);

    my $with = '';
    $with .= "     search_org_list AS (\n";
    if ($site < 0) {
        # Lasso!
        $lasso = -$site;
        $with .= "       SELECT DISTINCT org_unit from actor.org_lasso_map WHERE lasso = $lasso\n";
    } elsif ($site > 0) {
        $with .= "       SELECT DISTINCT id FROM actor.org_unit_descendants($site$depth_check)\n";
    } else {
        # Placeholder for user lasso stuff.
    }
    $with .= "     ),\n";
    $with .= "     luri_org_list AS (\n";
    if ($site < 0) {
        # We can re-use the lasso var, we already updated it above.
        $with .= "       SELECT DISTINCT (actor.org_unit_ancestors(org_unit)).id from actor.org_lasso_map WHERE lasso = $lasso\n";
    } elsif ($site > 0) {
        $with .= "       SELECT DISTINCT id FROM actor.org_unit_ancestors($site)\n";
    } else {
        # Placeholder for user lasso stuff.
    }
    if ($pref_ou) {
        $with .= "       UNION\n";
        $with .= "       SELECT DISTINCT id FROM actor.org_unit_ancestors($pref_ou)\n";
    }
    $with .= "     )";
    $with .= ",\n     " . $$flat_plan{with} if ($$flat_plan{with});

    # Limit stuff
    my $limit_where = <<"    SQL";
-- Filter records based on visibility
        AND (
            cbs.transcendant IS TRUE
            OR
            EXISTS(
                SELECT 1 FROM asset.call_number acn
                    JOIN asset.uri_call_number_map aucnm ON acn.id = aucnm.call_number
                    JOIN asset.uri uri ON aucnm.uri = uri.id
                WHERE NOT acn.deleted AND uri.active AND acn.record = m.source AND acn.owning_lib IN (
                    SELECT * FROM luri_org_list
                )
                LIMIT 1
            )
            OR
    SQL
    if ($self->find_modifier('staff')) {
        $limit_where .= <<"        SQL";
            EXISTS(
                SELECT 1 FROM asset.call_number cn
                    JOIN asset.copy cp ON (cp.call_number = cn.id)
                WHERE NOT cn.deleted
                    AND NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search_org_list )
                    AND cn.record = m.source
                LIMIT 1
            )
            OR
            EXISTS(
                SELECT 1 FROM biblio.peer_bib_copy_map pr
                    JOIN asset.copy cp ON (cp.id = pr.target_copy)
                WHERE NOT cp.deleted
                    AND cp.circ_lib IN ( SELECT * FROM search_org_list )
                    AND pr.peer_record = m.source
                LIMIT 1
            )
            OR (
                NOT EXISTS(
                    SELECT 1 FROM asset.call_number cn
                        JOIN asset.copy cp ON (cp.call_number = cn.id)
                    WHERE cn.record = m.source
                        AND NOT cp.deleted
                    LIMIT 1
                )
                AND
                NOT EXISTS(
                    SELECT 1 FROM biblio.peer_bib_copy_map pr
                        JOIN asset.copy cp ON (cp.id = pr.target_copy)
                    WHERE NOT cp.deleted
                        AND pr.peer_record = m.source
                    LIMIT 1
                )
            )
        SQL
    } else {
        $limit_where .= <<"        SQL";
            EXISTS(
                SELECT 1 FROM asset.opac_visible_copies
                WHERE circ_lib IN ( SELECT * FROM search_org_list )
                    AND record = m.source
                LIMIT 1
            )
            OR
            EXISTS(
                SELECT 1 FROM biblio.peer_bib_copy_map pr
                    JOIN asset.opac_visible_copies cp ON (cp.copy_id = pr.target_copy)
                WHERE cp.circ_lib IN ( SELECT * FROM search_org_list )
                    AND pr.peer_record = m.source
                LIMIT 1
            )
        SQL
    }
    $limit_where .= "        )";

    # For single records we want the record id
    # For metarecords we want NULL or the only record ID.
    my $agg_record = 'm.source AS record';
    if ($key =~ /metarecord/) {
        $agg_record = 'CASE WHEN COUNT(DISTINCT m.source) = 1 THEN FIRST(m.source) ELSE NULL END AS record';
    }

    my $sql = <<SQL;
WITH
$with
SELECT  $key AS id,
        $agg_record,
        $rel AS rel,
        $rank AS rank, 
        FIRST(mrd.attrs->'date1') AS tie_break
  FROM  metabib.metarecord_source_map m
        $$flat_plan{from}
        INNER JOIN metabib.record_attr mrd ON m.source = mrd.id
        INNER JOIN biblio.record_entry bre ON m.source = bre.id
        LEFT JOIN config.bib_source cbs ON bre.source = cbs.id
  WHERE 1=1
        $flat_where
        $limit_where
  GROUP BY 1
  ORDER BY 4 $desc $nullpos, 5 DESC $nullpos, 3 DESC
  LIMIT $core_limit
SQL

    warn $sql if $self->QueryParser->debug;
    return $sql;

}


sub rel_bump {
    my $self = shift;
    my $node = shift;
    my $bump = shift;
    my $multiplier = shift;

    my $only_atoms = $node->only_atoms;
    return '' if (!@$only_atoms);

    if ($bump eq 'first_word') {
        return "/* first_word */ COALESCE(NULLIF( (search_normalize(".$node->table_alias.".value) ~ ('^'||search_normalize(".$self->QueryParser->quote_phrase_value($only_atoms->[0]->content)."))), FALSE )::INT * $multiplier, 1)";
    } elsif ($bump eq 'full_match') {
        return "/* full_match */ COALESCE(NULLIF( (search_normalize(".$node->table_alias.".value) ~ ('^'||".
                    join( "||' '||", map { "search_normalize(".$self->QueryParser->quote_phrase_value($_->content).")" } @$only_atoms )."||'\$')), FALSE )::INT * $multiplier, 1)";
    } elsif ($bump eq 'word_order') {
        return "/* word_order */ COALESCE(NULLIF( (search_normalize(".$node->table_alias.".value) ~ (".
                    join( "||'.*'||", map { "search_normalize(".$self->QueryParser->quote_phrase_value($_->content).")" } @$only_atoms ).")), FALSE )::INT * $multiplier, 1)";
    }

    return '';
}

sub flatten {
    my $self = shift;

    my $from = shift || '';
    my $where = shift || '(';
    my $with = '';

    my @rank_list;
    for my $node ( @{$self->query_nodes} ) {

        if (ref($node)) {
            if ($node->isa( 'QueryParser::query_plan::node' )) {

                unless (@{$node->only_atoms}) {
                    push @rank_list, '1';
                    $where .= 'TRUE';
                    next;
                }

                my $table = $node->table;
                my $talias = $node->table_alias;

                my $node_rank = 'COALESCE(' . $node->rank . " * ${talias}.weight, 0.0)";

                my $core_limit = $self->QueryParser->core_limit || 25000;
                $from .= "\n${spc}${spc}${spc}${spc}LEFT JOIN (\n${spc}${spc}${spc}${spc}${spc}SELECT fe.*, fe_weight.weight, ${talias}_xq.tsq /* search */\n${spc}${spc}${spc}${spc}${spc}  FROM  $table AS fe";
                $from .= "\n${spc}${spc}${spc}${spc}${spc}${spc}JOIN config.metabib_field AS fe_weight ON (fe_weight.id = fe.field)";

                if ($node->dummy_count < @{$node->only_atoms} ) {
                    $with .= ",\n     " if $with;
                    $with .= "${talias}_xq AS (SELECT ". $node->tsquery ." AS tsq )";
                    $from .= "\n${spc}${spc}${spc}${spc}${spc}${spc}JOIN ${talias}_xq ON (fe.index_vector @@ ${talias}_xq.tsq)";
                } else {
                    $from .= "\n${spc}${spc}${spc}${spc}${spc}${spc}, (SELECT NULL::tsquery AS tsq ) AS ${talias}_xq";
                }

                my @bump_fields;
                if (@{$node->fields} > 0) {
                    @bump_fields = @{$node->fields};

                    my @field_ids = grep defined, (
                        map {
                            $self->QueryParser->search_field_ids_by_class(
                                $node->classname, $_
                            )->[0]
                        } @bump_fields
                    );
                    if (@field_ids) {
                        $from .= "\n${spc}${spc}${spc}${spc}${spc}${spc}WHERE fe_weight.id IN  (" .
                            join(',', @field_ids) . ")";
                    }

                } else {
                    @bump_fields = @{$self->QueryParser->search_fields->{$node->classname}};
                }

                ###$from .= "\n${spc}${spc}LIMIT $core_limit";
                $from .= "\n${spc}${spc}${spc}${spc}) AS $talias ON (m.source = ${talias}.source)";


                my %used_bumps;
                for my $field ( @bump_fields ) {
                    my $bumps = $self->QueryParser->find_relevance_bumps( $node->classname => $field );
                    for my $b (keys %$bumps) {
                        next if (!$$bumps{$b}{active});
                        next if ($used_bumps{$b});
                        $used_bumps{$b} = 1;

                        next if ($$bumps{$b}{multiplier} == 1); # optimization to remove unneeded bumps

                        my $bump_case = $self->rel_bump( $node, $b, $$bumps{$b}{multiplier} );
                        $node_rank .= "\n${spc}${spc}${spc}${spc}${spc}* " . $bump_case if ($bump_case);
                    }
                }


                $where .= '(' . $talias . ".id IS NOT NULL";
                $where .= ' AND ' . join(' AND ', map {"${talias}.value ~* ".$self->QueryParser->quote_phrase_value($_)} @{$node->phrases}) if (@{$node->phrases});
                $where .= ' AND ' . join(' AND ', map {"${talias}.value !~* ".$self->QueryParser->quote_phrase_value($_)} @{$node->unphrases}) if (@{$node->unphrases});
                $where .= ')';

                push @rank_list, $node_rank;

            } elsif ($node->isa( 'QueryParser::query_plan::facet' )) {

                my $table = $node->table;
                my $talias = $node->table_alias;

                my @field_ids;
                if (@{$node->fields} > 0) {
                    push(@field_ids, $self->QueryParser->facet_field_ids_by_class( $node->classname, $_ )->[0]) for (@{$node->fields});
                } else {
                    @field_ids = @{ $self->QueryParser->facet_field_ids_by_class( $node->classname ) };
                }

                my $join_type = ($node->negate or !$self->top_plan) ? 'LEFT' : 'INNER';
                $from .= "\n${spc}$join_type JOIN /* facet */ metabib.facet_entry $talias ON (\n${spc}${spc}m.source = ${talias}.source\n${spc}${spc}".
                         "AND SUBSTRING(${talias}.value,1,1024) IN (" . join(",", map { $self->QueryParser->quote_value($_) } @{$node->values}) . ")\n${spc}${spc}".
                         "AND ${talias}.field IN (". join(',', @field_ids) . ")\n${spc})";

                if ($join_type ne 'INNER') {
                    my $NOT = $node->negate ? '' : ' NOT';
                    $where .= "${talias}.id IS$NOT NULL";
                } elsif ($where ne '(') {
                    # Strip extra joiner
                    $where =~ s/\s(AND|OR)\s$//;
                }

            } else {
                my $subnode = $node->flatten;

                # strip the trailing bool from the previous loop if there is 
                # nothing to add to the where within this loop.
                if ($$subnode{where} eq '()') {
                    $where =~ s/\s(AND|OR)\s$//;
                }

                push(@rank_list, @{$$subnode{rank_list}});
                $from .= $$subnode{from};

                $where .= "$$subnode{where}" unless $$subnode{where} eq '()';

                if ($$subnode{with}) {
                    $with .= ",\n     " if $with;
                    $with .= $$subnode{with};
                }
            }
        } else {

            warn "flatten(): appending WHERE bool to: $where\n" if $self->QueryParser->debug;

            if ($where ne '(') {
                $where .= ' AND ' if ($node eq '&');
                $where .= ' OR ' if ($node eq '|');
            }
        }
    }

    my $joiner = sprintf(" %s ", ($self->joiner eq '&' ? 'AND' : 'OR'));
    # for each dynamic filter, build more of the WHERE clause
    for my $filter (@{$self->filters}) {
        if (grep { $_ eq $filter->name } @{ $self->QueryParser->dynamic_filters }) {

            warn "flatten(): processing dynamic filter ". $filter->name ."\n"
                if $self->QueryParser->debug;

            # bool joiner for intra-plan nodes/filters
            $where .= $joiner if $where ne '(';

            my @fargs = @{$filter->args};
            my $NOT = $filter->negate ? ' NOT' : '';
            my $fname = $filter->name;
            $fname = 'item_lang' if $fname eq 'language'; #XXX filter aliases 

            $where .= sprintf(
                "attrs->'%s'$NOT IN (%s)", $fname, 
                join(',', map { $self->QueryParser->quote_value($_) } @fargs)
            );

            warn "flatten(): filter where => $where\n"
                if $self->QueryParser->debug;
        } else {
            my $NOT = $filter->negate ? 'NOT ' : '';
            switch ($filter->name) {
                case 'before' {
                    if (@{$filter->args} == 1) {
                        $where .= $joiner if $where ne '(';
                        $where .= "$NOT(mrd.attrs->'date1') <= " . $self->QueryParser->quote_value($filter->args->[0]);
                    }
                }
                case 'after' {
                    if (@{$filter->args} == 1) {
                        $where .= $joiner if $where ne '(';
                        $where .= "$NOT(mrd.attrs->'date1') >= " . $self->QueryParser->quote_value($filter->args->[0]);
                    }
                }
                case 'during' {
                    if (@{$filter->args} == 1) {
                        $where .= $joiner if $where ne '(';
                        $where .= $self->QueryParser->quote_value($filter->args->[0]) . " ${NOT}BETWEEN (mrd.attrs->'date1') AND (mrd.attrs->'date2')";
                    }
                }
                case 'between' {
                    if (@{$filter->args} == 2) {
                        $where .= $joiner if $where ne '(';
                        $where .= "(mrd.attrs->'date1') ${NOT}BETWEEN " . $self->QueryParser->quote_value($filter->args->[0]) . " AND " . $self->QueryParser->quote_value($filter->args->[1]);
                    }
                }
                case 'container' {
                    if (@{$filter->args} >= 3) {
                        my ($class, $ctype, $cid, $token) = @{$filter->args};
                        my $perm_join = '';
                        my $rec_join = '';
                        my $rec_field = 'ci.target_biblio_record_entry';
                        switch($class) {
                            case 'bre' {
                                $class = 'biblio_record_entry';
                            }
                            case 'acn' {
                                $class = 'call_number';
                                $rec_field = 'cn.record';
                                $rec_join = 'JOIN asset.call_number cn ON (ci.target_call_number = cn.id)';
                            }
                            case 'acp' {
                                $class = 'copy';
                                $rec_field = 'cn.record';
                                $rec_join = 'JOIN asset.copy cp ON (ci.target_copy = cp.id) JOIN asset.call_number cn ON (cp.call_number = cn.id)';
                            }
                            else {
                                $class = undef;
                            }
                        }

                        if ($class) {
                            my ($u,$e) = $apputils->checksesperm($token) if ($token);
                            $perm_join = ' OR c.owner = ' . $u->id if ($u && !$e);
                            $where .= $joiner if $where ne '(';
                            $where .= '(' if $class eq 'copy';
                            $where .= "${NOT}EXISTS(SELECT 1 FROM container.${class}_bucket_item ci JOIN container.${class}_bucket c ON (c.id = ci.bucket) $rec_join WHERE c.btype = " . $self->QueryParser->quote_value($ctype) . " AND c.id = " . $self->QueryParser->quote_value($cid) . " AND (c.pub IS TRUE$perm_join) AND $rec_field = m.source LIMIT 1)";
                        }
                        if ($class eq 'copy') {
                            my $subjoiner = $filter->negate ? ' AND ' : ' OR ';
                            $where .= "$subjoiner${NOT}EXISTS(SELECT 1 FROM container.copy_bucket_item ci JOIN container.copy_bucket c ON (c.id = ci.bucket) JOIN biblio.peer_bib_copy_map pr ON ci.target_copy = pr.target_copy WHERE c.btype = " . $self->QueryParser->quote_value($cid) . " AND (c.pub IS TRUE$perm_join) AND pr.peer_record = m.source LIMIT 1))";
                        }
                    }
                }
                case 'record_list' {
                    if (@{$filter->args} > 0) {
                        my $key = 'm.source';
                        $key = 'm.metarecord' if (grep {$_->name eq 'metarecord' or $_->name eq 'metabib'} @{$self->QueryParser->parse_tree->modifiers});
                        $where .= $joiner if $where ne '(';
                        $where .= "$key ${NOT}IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{$filter->args}) . ')';
                    }
                }
                case 'locations' {
                    if (@{$filter->args} > 0) {
                        $where .= $joiner if $where ne '(';
                        $where .= "(${NOT}EXISTS(SELECT 1 FROM asset.call_number acn JOIN asset.copy acp ON acn.id = acp.call_number WHERE m.source = acn.record AND acp.circ_lib IN (SELECT * FROM search_org_list) AND NOT acn.deleted AND NOT acp.deleted AND acp.location IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{ $filter->args }) . ") LIMIT 1)";
                        $where .= $filter->negate ? ' AND ' : ' OR ';
                        $where .= "${NOT}EXISTS(SELECT 1 FROM biblio.peer_bib_copy_map pr JOIN asset.copy acp ON pr.target_copy = acp.id WHERE m.source = pr.peer_record AND acp.circ_lib IN (SELECT * FROM search_org_list) AND NOT acp.deleted AND acp.location IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{ $filter->args }) . ") LIMIT 1))";
                    }
                }
                case 'statuses' {
                    if (@{$filter->args} > 0) {
                        $where .= $joiner if $where ne '(';
                        $where .= "(${NOT}EXISTS(SELECT 1 FROM asset.call_number acn JOIN asset.copy acp ON acn.id = acp.call_number WHERE m.source = acn.record AND acp.circ_lib IN (SELECT * FROM search_org_list) AND NOT acn.deleted AND NOT acp.deleted AND acp.status IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{ $filter->args }) . ") LIMIT 1)";
                        $where .= $filter->negate ? ' AND ' : ' OR ';
                        $where .= "${NOT}EXISTS(SELECT 1 FROM biblio.peer_bib_copy_map pr JOIN asset.copy acp ON pr.target_copy = acp.id WHERE m.source = pr.peer_record AND acp.circ_lib IN (SELECT * FROM search_org_list) AND NOT acp.deleted AND acp.status IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{ $filter->args }) . ") LIMIT 1))";
                    }
                }
                case 'bib_source' {
                    if (@{$filter->args} > 0) {
                        $where .= $joiner if $where ne '(';
                        $where .= "bre.source IN (" . join(',', map { $self->QueryParser->quote_value($_) } @{ $filter->args }) . ")";
                    }
                }
            }
        }
    }
    warn "flatten(): full filter where => $where\n" if $self->QueryParser->debug;

    return { rank_list => \@rank_list, from => $from, where => $where.')',  with => $with };
}


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::filter;
use base 'QueryParser::query_plan::filter';

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::facet;
use base 'QueryParser::query_plan::facet';

sub classname {
    my $self = shift;
    my ($classname) = split '\|', $self->name;
    return $classname;
}

sub table {
    my $self = shift;
    return 'metabib.' . $self->classname . '_field_entry';
}

sub fields {
    my $self = shift;
    my ($classname,@fields) = split '\|', $self->name;
    return \@fields;
}

sub table_alias {
    my $self = shift;

    my $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->name;
    $table_alias =~ s/\|/_/go;

    return $table_alias;
}


#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::modifier;
use base 'QueryParser::query_plan::modifier';

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::node::atom;
use base 'QueryParser::query_plan::node::atom';

sub sql {
    my $self = shift;
    my $sql = shift;

    $self->{sql} = $sql if ($sql);

    return $self->{sql} if ($self->{sql});
    return $self->buildSQL;
}

sub buildSQL {
    my $self = shift;

    my $classname = $self->node->classname;

    return $self->sql("to_tsquery('$classname','')") if $self->{dummy};

    my $normalizers = $self->node->plan->QueryParser->query_normalizers( $classname );
    my $fields = $self->node->fields;

    $fields = $self->node->plan->QueryParser->search_fields->{$classname} if (!@$fields);

    my %norms;
    my $pos = 0;
    for my $field (@$fields) {
        for my $nfield (keys %$normalizers) {
            for my $nizer ( @{$$normalizers{$nfield}} ) {
                if ($field eq $nfield) {
                    my $param_string = OpenSRF::Utils::JSON->perl2JSON($nizer->{params});
                    if (!exists($norms{$nizer->{function}.$param_string})) {
                        $norms{$nizer->{function}.$param_string} = {p=>$pos++,n=>$nizer};
                    }
                }
            }
        }
    }

    my $sql = $self->node->plan->QueryParser->quote_value($self->content);

    for my $n ( map { $$_{n} } sort { $$a{p} <=> $$b{p} } values %norms ) {
        $sql = join(', ', $sql, map { $self->node->plan->QueryParser->quote_value($_) } @{ $n->{params} });
        $sql = $n->{function}."($sql)";
    }

    my $prefix = $self->prefix || '';
    my $suffix = $self->suffix || '';

    $prefix = "'$prefix' ||" if $prefix;
    my $suffix_op = '';
    my $suffix_after = '';

    $suffix_op = ":$suffix" if $suffix;
    $suffix_after = "|| '$suffix_op'" if $suffix;

    $sql = "to_tsquery('$classname', COALESCE(NULLIF($prefix '(' || btrim(regexp_replace($sql,E'(?:\\\\s+|:)','$suffix_op&','g'),'&|') $suffix_after || ')', '()'), ''))";

    return $self->sql($sql);
}

#-------------------------------
package OpenILS::Application::Storage::Driver::Pg::QueryParser::query_plan::node;
use base 'QueryParser::query_plan::node';

sub only_atoms {
    my $self = shift;

    $self->{dummy_count} = 0;

    my $atoms = $self->query_atoms;
    my @only_atoms;
    for my $a (@$atoms) {
        push(@only_atoms, $a) if (ref($a) && $a->isa('QueryParser::query_plan::node::atom'));
        $self->{dummy_count}++ if (ref($a) && $a->{dummy});
    }

    return \@only_atoms;
}

sub dummy_count {
    my $self = shift;
    return $self->{dummy_count};
}

sub table {
    my $self = shift;
    my $table = shift;
    $self->{table} = $table if ($table);
    return $self->{table} if $self->{table};
    return $self->table( 'metabib.' . $self->classname . '_field_entry' );
}

sub table_alias {
    my $self = shift;
    my $table_alias = shift;
    $self->{table_alias} = $table_alias if ($table_alias);
    return $self->{table_alias} if ($self->{table_alias});

    $table_alias = "$self";
    $table_alias =~ s/^.*\(0(x[0-9a-fA-F]+)\)$/$1/go;
    $table_alias .= '_' . $self->requested_class;
    $table_alias =~ s/\|/_/go;

    return $self->table_alias( $table_alias );
}

sub tsquery {
    my $self = shift;
    return $self->{tsquery} if ($self->{tsquery});

    for my $atom (@{$self->query_atoms}) {
        if (ref($atom)) {
            $self->{tsquery} .= "\n${spc}${spc}${spc}" .$atom->sql;
        } else {
            $self->{tsquery} .= $atom x 2;
        }
    }

    return $self->{tsquery};
}

sub rank {
    my $self = shift;

    my $rank_norm_map = $self->plan->QueryParser->custom_data->{rank_cd_weight_map};

    my $cover_density = 0;
    for my $norm ( keys %$rank_norm_map) {
        $cover_density += $$rank_norm_map{$norm} if ($self->plan->find_modifier($norm));
    }

    return $self->{rank} if ($self->{rank});
    return $self->{rank} = 'ts_rank_cd(' . $self->table_alias . '.index_vector, ' . $self->table_alias . ".tsq, $cover_density)";
}


1;

