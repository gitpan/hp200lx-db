#!/usr/local/bin/perl
# FILE .../CPAN/hp200lx-db/scripts/catadb.pl
#
# print ADB file in vCalendar format
# see usage
#
# T2D:
# + use formalized vCalendar module
# + generate vCalendar object for each vTodo and vEvent object
# + additional vTodo properties:
#   + X-200LX-COMPLETED         (reflecting completion check mark)
#   + X-200LX-CARRY-OVER        (reflecting carry over check box)
# + export flags:
#   + begin and end date (default: all)
#   + type: only To-Dos, Events, Dates ...
# + analyze notes field
#
# written:       1998-09-20
# latest update: 1999-02-22 20:38:52
#

use HP200LX::DB;
use HP200LX::DB::recurrence;
use HP200LX::DB::tools;

$Author= 'g.gonter@ieee.org';
$Application= 'HP200LX::DB catadb.pl';
$Appl_Version= '0.06';

$format= 'vcs';
$folding= 'rfc';        # none, rfc [DEFAULT], simple
$show_db_def= $show_diag= 0;
$select= 'all'; # all or table

%LANG=
(
  'German' =>
  {
    # Both
    'SUMMARY'         => 'Beschreib.',
    'CATEGORIES'      => 'Kategorie',           # how can this be set??
    'DTSTART'         => 'Beginndatum',         # append time!
    'DESCRIPTION'     => 'Notiz',

    # Date/Event
    'START_TIME'      => 'Beginnzeit',
    'END_TIME'        => 'Endzeit   ',
    'ALARM'           => 'Meldung',
    'ALARM_ADV'       => 'Vorlauf',
    'LOCATION'        => 'Ort      ',
    'X-200LX-NUM-DAYS'  => "# aufein\'folg. Tage",

    # To-Do
    'X-200LX-DUE'       => "F\204lligkeitstermin ",   # Offset it days! (T2D)
    'COMPLETED'         => "Abschlu\341datum",
    'X-200LX-PRIORITY'  => 'Priorit\204t   ',
  },

  'English' =>
  {
    # Both
    'SUMMARY'         => 'Description',
    'CATEGORIES'      => 'Category',           # how can this be set??
    'DTSTART'         => 'Start Date ',         # append time!
    'DESCRIPTION'     => 'Note',

    # Date/Event
    'START_TIME'      => 'Start Time ',
    'END_TIME'        => 'End Time   ',
    'ALARM'           => 'Alarm',
    'ALARM_ADV'       => 'Leadtime',
    'LOCATION'        => 'Location   ',
    'X-200LX-NUM-DAYS'  => '#Consecutive Days',

    # To-Do
    'X-200LX-DUE'       => 'Due Date   ',   # Offset it days! (T2D)
    'COMPLETED'         => 'Completion Date',
    'X-200LX-PRIORITY'  => 'Priority   ',
  },
);

local *FO;
my $fnm_out;

ARGUMENT: while (defined ($arg= shift (@ARGV)))
{
  if ($arg =~ /^-/)
  {
    if ($arg eq '-')            { push (@JOBS, $arg);           }
    elsif ($arg eq '-dbdef')    { $show_db_def= 1;              }
    elsif ($arg eq '-diag')     { $show_diag= 1;                }
    elsif ($arg eq '-folding')  { $folding= shift (@ARGV);      }
    elsif ($arg eq '-select')   { $select= shift (@ARGV);       }
    elsif ($arg eq '-format')   { $format= shift (@ARGV);       }
    elsif ($arg eq '-o' || $arg eq '-a')
    {
      $fnm_out= shift (@ARGV);
      open (FO, ($arg eq '-o') ? ">$fnm_out" : ">>$fnm_out") || die;
    }
    else
    {
      &usage;
      exit (0);
    }
    next;
  }

  push (@JOBS, $arg);
}

*FO= *STDOUT unless ($fnm_out);
foreach $job (@JOBS)
{
  if ($format eq 'vcs') { &print_adb_vcs (*FO, $job); }
  else { &usage; }
}

# cleanup
close (FO) if ($fnm_out);

exit (0);

# ----------------------------------------------------------------------------
sub usage
{
  print <<END_OF_USAGE
usage: $0 [-options] [filenanme]

Options:
-help                   ... print help
-o <file>               ... export data to output file
-for[mat] <format>      ... select presentation format
                            vcs: vCard [DEFAULT]
-folding <scheme>       ... folding scheme applied to contents lines:
                            rfc: folding according to RFC 2426 etc. [DEFAULT]
                            simple: insert blanks before next line
                            none: don't do anything special
-select <part>          ... select items to be used
                            all: display all items [DEFAULT]
                            table: display only items listed in view table(?)

-dbdef                  ... print database definition
-diag                   ... print diagnositc information

Examples:
  $0 -o export.vcs -folding simple appt.adb
END_OF_USAGE
}

# ----------------------------------------------------------------------------
sub select_language
{
  my $db= shift;

  my $desc= $db->get_field_def (0);
  my $desc_name= $desc->{name};

  foreach $lng (keys %LANG)
  {
    $lang= $LANG{$lng};
    if ($lang->{SUMMARY} eq $desc_name)
    {
      print "selecting langauge '$lng'\n" if ($show_diag);
      return $lang;
    }
  }

  print <<EO_NOTE;
unknown langauge, name of description field= '$desc_name' !
please send a sample of an appointment book in this language to
  g.gonter\@ieee.org
EO_NOTE

  return undef;
}

# ----------------------------------------------------------------------------
sub print_adb_vcs
{
  local *FO= shift;
  my $fnm= shift;

  my (@data, $i, $field, $val);

  my $db= HP200LX::DB::openDB ($fnm);

  my $lang= &select_language ($db);
  my $AD= $db->{APT_Data};
  my $table= $AD->{View_Table};

  if ($show_db_def)
  {
      print "database definition:\n:"; $db->show_db_def (*STDOUT);
      print "card definition:\n:";     $db->show_card_def (*STDOUT);
  }

  if ($show_diag)
  {
    print "header data of $fnm\n";
    print "    number of entries in view Table: ", $#$table, "\n";
    print "    head date=$AD->{Head_Date}\n";
    &HP200LX::DB::hex_dump ($AD->{Header}, *STDOUT);

    print '=' x72, "\n\n";
  }

  my $db_cnt= $db->get_last_index ();
  # tie (@data, HP200LX::DB, $db);

  if ($folding eq 'simple' || $folding eq 'none') { $VERSION= '1.0'; }
  elsif ($folding eq 'rfc') { $VERSION= '2.0'; }

  print FO <<EO_VCS;
BEGIN:VCALENDAR
VERSION:$VERSION
PRODID:-//$Author//NONSGML $Application $Appl_Version//EN

EO_VCS

  if ($select eq 'all')
  {
    for ($i= 0; $i <= $db_cnt; $i++) { &print_entry (*FO, $db, $i); }
  }
  elsif ($select eq 'table')
  {
    my $ptr;
    foreach $ptr (@$table)
    {
      print "entry date: $ptr->{'date'}\n";
      &print_entry (*FO, $db, $ptr->{num});
    }
  }

  print FO "END:VCALENDAR\n\n";

}

# ----------------------------------------------------------------------------
sub print_entry
{
  local *FO= shift;
  my $db= shift;
  my $idx= shift;
  my $blk;

  my $rec= $db->FETCH ($idx);
  return unless (defined ($rec));
  my $raw= $db->FETCH_raw ($idx);

  print "entry number: $idx\n" if ($show_diag);
  my $entry_type= $rec->{type};
  my $recurrence;

    my ($v1, $cat, $loc, $v2, $n, $v3, $v4)= unpack ('vvvvvvv', $raw);

    if ($v2 < length ($raw))
    {
      $recurrence= new HP200LX::DB::recurrence ($rec->{repeat},
                      $blk= substr ($raw, $v2));
    }

    if ($entry_type eq 'Date')
    {
      print FO <<EO_VCS;
BEGIN:VEVENT
CATEGORIES:PERSONAL
CLASS:PRIVATE
EO_VCS

      my $start_time= $rec->{$lang->{START_TIME}};
      my $dt_start= &get_dt ($rec->{$lang->{DTSTART}}, $start_time);
      my $dt_end=   &get_dt ($rec->{$lang->{DTSTART}},
                             $rec->{$lang->{END_TIME}});

      print FO "DTSTART:$dt_start\n";
      print FO "DTEND:$dt_end\n";

      &print_recurrence (*FO, $recurrence, 'T'.$start_time.':00');

      &print_list (*FO, $rec, $lang, 0, $folding, 'SUMMARY', 'LOCATION', 'DESCRIPTION');
      &print_list (*FO, $rec, $lang, 1, $folding, 'X-200LX-NUM-DAYS');

      print FO "END:VEVENT\n\n";
    }
    else
    {
      print FO <<EO_VCS;
BEGIN:VTODO
CATEGORIES:PERSONAL
CLASS:PRIVAT
EO_VCS

      foreach $field ('DTSTART', 'COMPLETED')
      {
        $val= $rec->{$lang->{$field}};
        next if ($val eq '2155-256-01');
        # $val=~ s/-//g;
        print FO $field, ':', $val, "T00:00:00\n";
      }

      &print_recurrence (*FO, $recurrence);

      &print_list (*FO, $rec, $lang, 0, $folding, 'SUMMARY', 'DESCRIPTION',
                                        'X-200LX-PRIORITY');
      &print_list (*FO, $rec, $lang, 1, $folding, 'X-200LX-DUE');

      print FO "END:VTODO\n\n";
    }

    if ($show_diag)
    {
      my $fld;
      foreach $fld (sort keys %$rec)
      {
        print $fld, '=', $rec->{$fld}, "\n";
      }
    }

    # &HP200LX::DB::hex_dump ($raw, *STDOUT);
    if ($recurrence && $show_diag)
    {
      printf ("YYY v1=0x%04X v2=0x%04X v3=0x%04X v4=0x%04X lng=0x%04X\n",
            $v1, $v2, $v3, $v4, length ($raw));
      # print "repeats:\n";
      $recurrence->print_recurrence_status (*STDOUT);

      print "recurrence data\n";
      &HP200LX::DB::hex_dump ($blk, *STDOUT);

    }
      print "record data\n";
      &HP200LX::DB::hex_dump ($raw, *STDOUT);

    print '=' x72, "\n\n" if ($show_diag);
}

# ----------------------------------------------------------------------------
sub print_recurrence
{
  local *FO= shift;
  my $recurrence= shift;
  my $start_time= shift;

  return unless ($recurrence);

  my $vc_rec= $recurrence->export_to_vCalendar ($start_time);
  my $k;

  foreach $k (keys %$vc_rec)
  { # T2D: Folding!!!
    &print_content_line (*FO, $k, $vc_rec->{$k}, $folding, 1);
  }
}

# ----------------------------------------------------------------------------
sub get_dt
{
  my $date= shift;
  my $time= shift;

  # $date=~ s/-//g;
  # $time=~ s/://g;
  $date . 'T' . $time . ':00';
}
