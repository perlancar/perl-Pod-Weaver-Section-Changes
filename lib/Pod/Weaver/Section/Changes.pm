package Pod::Weaver::Section::Changes;

use 5.010001;
use Moose;
with 'Pod::Weaver::Role::Section';

use Log::Any '$log';

use Config::INI::Reader;
use CPAN::Changes;
use Moose::Autobox;
use Pod::Elemental;
use Pod::Elemental::Element::Nested;

# VERSION

# regex
has exclude_modules => (
    is => 'rw',
    isa => 'Str',
);
has exclude_files => (
    is => 'rw',
    isa => 'Str',
);

sub weave_section {
    $log->trace("-> ".__PACKAGE__."::weave_section()");
    my ($self, $document, $input) = @_;

    my $filename = $input->{filename} || 'file';

    # try to find main package name, from dist.ini. there should be a better
    # way.
    my $ini = Config::INI::Reader->read_file('dist.ini');
    my $main_package = $ini->{_}{name};
    $main_package =~ s/-/::/g;

    # guess package name from filename
    my $package;
    if ($filename =~ m!^lib/(.+)\.(?:pm|pod)$!) {
        $package = $1;
        $package =~ s!/!::!g;
    } else {
        $log->debugf("skipped file %s (not a Perl module)", $filename);
        return;
    }

    if ($package ne $main_package) {
        $log->debugf("skipped file %s (not main module)", $filename);
        return;
    }

    if (defined $self->exclude_files) {
        my $re = $self->exclude_files;
        eval { $re = qr/$re/ };
        $@ and die "Invalid regex in exclude_files: $re";
        if ($filename =~ $re) {
            $self->log (["skipped file %s (matched exclude_files)", $filename]);
            $log->debugf("skipped file %s (matched exclude_files)", $filename);
            return;
        }
    }
    if (defined $self->exclude_modules) {
        my $re = $self->exclude_modules;
        eval { $re = qr/$re/ };
        $@ and die "Invalid regex in exclude_modules: $re";
        if ($package =~ $re) {
            $self->log (["skipped package %s (matched exclude_modules)", $package]);
            $log->debugf("skipped package %s (matched exclude_modules)", $package);
            return;
        }
    }

    my $changes;
    for my $f (qw/Changes CHANGES ChangeLog CHANGELOG/) {
        if (-f $f) {
            $changes = CPAN::Changes->load($f);
            last;
        }
    }

    unless ($changes) {
        $self->log(["skipped adding CHANGES section to %s (no valid Changes file)", $filename]);
        $log->infof("skipped adding CHANGES section to %s (no valid Changes file)", $filename );
        return;
    }

    my @content;
    for my $rel (reverse $changes->releases) {
        my @rel_changes;
        my $rchanges = $rel->changes;
        for my $cgrp (sort keys %$rchanges) {
            push @rel_changes, Pod::Elemental::Element::Pod5::Command->new({
                command => 'over',
                content => '4',
            });
            for my $c (@{ $rchanges->{$cgrp} }) {
                push @rel_changes, Pod::Elemental::Element::Nested->new({
                    command => 'item',
                    content => '*',
                    children => [Pod::Elemental::Element::Pod5::Ordinary->new({
                        content => ($cgrp ? "[$cgrp] " : "") . $c,
                    })]
                });
            }
            push @rel_changes, Pod::Elemental::Element::Pod5::Command->new({
                command => 'back',
                content => '',
            });
        }

        push @content, Pod::Elemental::Element::Nested->new({
            command => 'head2',
            content => "Version " . $rel->version . " (". $rel->date . ")",
            children => \@rel_changes,
        });
    }

    $document->children->push(
        Pod::Elemental::Element::Nested->new({
            command  => 'head1',
            content  => 'CHANGES',
            children => \@content,
        }),
    );

    $self->log(["added CHANGES section to %s", $filename]);
    $log->infof("added CHANGES section to %s", $filename );

    $log->trace("<- ".__PACKAGE__."::weave_section()");
}

1;
# ABSTRACT: Add a CHANGES POD section

=for Pod::Coverage weave_section

=head1 SYNOPSIS

In your C<weaver.ini>:

 [Changes]


=head1 DESCRIPTION

Inserting information in distribution's C<Changes> to main module's POD can be a
convenience for your module users.

Changes is parsed using L<CPAN::Changes> and markup in text entries are
currently assumed to be POD too.


=head1 SEE ALSO

L<Pod::Weaver>

L<CPAN::Changes>
