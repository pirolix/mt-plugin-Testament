package MT::Plugin::OMV::Testament;
# Testament - 
#       Copyright (c) 2008 Piroli YUKARINOMIYA (MagicVox)

use strict;
use MT;
use MT::Author;
use MT::PluginData;
use MT::Log;
#use Data::Dumper;#DEBUG

use constant DEFAULT_ACTION => 0;
use constant DEFAULT_STAY   => 30;
use constant DEFAULT_FATE   => 0;

use vars qw( $MYNAME $VERSION );
$MYNAME = 'Testament';
$VERSION = '0.01';

use base qw( MT::Plugin );
my $plugin = __PACKAGE__->new({
    name => $MYNAME,
    id => lc $MYNAME,
    key => lc $MYNAME,
    version => $VERSION,
    description => <<HTMLHEREDOC,
Testamentary executor.
HTMLHEREDOC
});
MT->add_plugin( $plugin );

sub instance { $plugin; }

### Registry
sub init_registry {
    my $plugin = shift;
    $plugin->registry({
        callbacks => {
           'MT::App::CMS::template_source.edit_author' => \&_source_edit_author,
           'MT::App::CMS::template_param.edit_author' => \&_params_edit_author,
           'MT::Author::post_save' => \&_hdlr_save_author,

           'MT::App::CMS::template_param.header' => \&_params_header,
        },
        tasks => {
            ExecuteTestament => {
                name        => 'Testamentary executor',
                frequency   => 60 * 60,
                code        => \&_hdlr_execute_testament,
            },
        },
    });
}



###
sub _source_edit_author {
    my ($eh, $app, $tmpl) = @_;

    my $old = quotemeta( <<'HTMLHEREDOC' );
            <fieldset>
                <h3><__trans phrase="System Permissions"><a href="javascript:void(0)" onclick="return openManual('author_permissions', 'introduction')" class="help-link">?</a></h3>
HTMLHEREDOC
    my $new = <<'HTMLHEREDOC';
<fieldset>
    <h3><__trans phrase="Last will and Testament"></h3>

    <mtapp:setting
        id="stay"
        label="<__trans phrase="Action">"
        hint="">
        <select name="action">
            <option>Eliminate all of my traces</option>
        </select>
    </mtapp:setting>

    <mtapp:setting
        id="stay"
        label="<__trans phrase="A stay of execution">"
        hint="">
        <input type="text" name="stay" id="stay" size="4" value="<TMPL_VAR NAME=TESTAMENT_STAY ESCAPE=HTML>" /> <__trans phrase="days">
    </mtapp:setting>

    <mtapp:setting
        id="fate"
        label="<__trans phrase="Fate">"
        hint="">
        <input type="checkbox" name="fate" id="fate" value="1"<TMPL_IF NAME=TESTAMENT_FATE> checked="checked"</TMPL_IF>/><label for="fate">Share everyone&apos;s</label>
    </mtapp:setting>
</fieldset>
HTMLHEREDOC
    $$tmpl =~ s/($old)/$new$1/;
}

###
sub _params_edit_author {
    my ($eh, $app, $params, $tmpl) = @_;

    my $testament = load_plugindata( key_name( $params->{id} || 0 ));# author_id
    $testament ||= {
        stay => DEFAULT_STAY,
        fate => DEFAULT_FATE,
    };
    $params->{testament_stay} = $testament->{stay};
    $params->{testament_fate} = $testament->{fate};
}

###
sub _hdlr_save_author {
    my ($rh, $obj) = @_;
    UNIVERSAL::isa( $obj, 'MT::Author' )
        or return;

    my $q = MT->instance->{query}
        or return;
    $q->param( '__mode' ) == 'view' && $q->param( '_type' ) == 'author'
        or return;
    my ($q_stay) = $q->param( 'stay' ) =~ m/^\s*(\d+)\s*$/;
    my ($q_fate) = $q->param( 'fate' ) =~ m/^1$/;

    my $testament = load_plugindata( key_name( $obj->id ));# author_id
    $testament ||= {};
    $testament->{stay} = defined $q_stay ? $q_stay : DEFAULT_STAY;
    $testament->{fate} = defined $q_fate ? $q_fate : DEFAULT_FATE;
    save_plugindata( key_name( $obj->id ), $testament );
}



###
sub _params_header {
    my ($eh, $app, $params, $tmpl) = @_;

    my $author_id = $params->{author_id}
        or return;
    my $testament = load_plugindata( key_name( $author_id ))
        or return;# do nothing
    $testament->{last_login} = time;
    save_plugindata( key_name( $author_id ), $testament );
}



###
sub _hdlr_execute_testament {
    my $author_iter = MT::Author->load_iter()
        or return;
    my %rebuild_blogs = ();
    while (my $author = $author_iter->()) {
        my $testament = load_plugindata( key_name( $author->id ))
            or next;
        defined( $testament->{last_login} )
            or next;
        0 < $testament->{stay}
            or next;
        if ($testament->{last_login} + $testament->{stay} * 24 * 60 * 60 < time) {
            my $entry_iter = $testament->{fate}
                ? MT::Entry->load_iter()
                : MT::Entry->load_iter({ author_id => $author->id });
            while (my $entry = $entry_iter->()) {
                $rebuild_blogs{$entry->blog_id} = 1;
                MT->instance->publisher->rebuild_deleted_entry( Entry => $entry );
                $entry->remove;
            }

            # Set not to re-work
            $testament->{stay} = 0;
            save_plugindata( key_name( $author->id ), $testament );

            # Logging
            my $log = MT::Log->new;
            $log->author_id( $author->id );
            $log->level( MT::Log::INFO());
            $log->message( $author->nickname. "'s last will and testament was executed." );
            $log->save;
        }
    }

    ### Rebuild the all affected blogs.
    foreach my $blog_id (keys %rebuild_blogs) {
        my $blog = MT::Blog->load({ id => $blog_id })
            or next;
        MT->instance->rebuild( Blog => $blog );
    }
}



########################################################################
sub key_name { 'author_id::'. $_[0]; }

sub save_plugindata {
    my ($key, $data_ref) = @_;
    my $pd = MT::PluginData->load({ plugin => &instance->id, key=> $key });
    if (!$pd) {
        $pd = MT::PluginData->new;
        $pd->plugin( &instance->id );
        $pd->key( $key );
    }
    $pd->data( $data_ref );
    $pd->save;
}

sub load_plugindata {
    my ($key) = @_;
    my $pd = MT::PluginData->load({ plugin => &instance->id, key=> $key })
        or return undef;
    $pd->data;
}

1;