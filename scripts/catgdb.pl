#!/usr/local/bin/perl
# FILE %usr/unixonly/hp200lx/catgdb.pl
#
# print data records of a HP 200LX DB 
#
# written:       1998-01-11
# latest update: 1999-05-23 13:59:22
#

use HP200LX::DB;
use HP200LX::DB::tools;

# initializiation
$FS= ';';
$RS= "\n";
$show_fields= 1;
$show_db_def= 0;
$show_notes= 1;
$format= 1;
$print_header= 1;

ARGUMENT: while (defined ($arg= shift (@ARGV)))
{
  if ($arg =~ /^-/)
  {
    if ($arg eq '-')            { push (@JOBS, $arg);   }
    elsif ($arg =~ /^-noh/)     { $show_fields= 0;      }
    elsif ($arg =~ /^-dbdef/)   { $show_db_def= 1;      }
    elsif ($arg =~ /^-nono/)    { $show_notes= 0;       }
    elsif ($arg =~ /^-for/)     { $format= shift (@ARGV); }
    elsif ($arg =~ /^-sum/)     { $format= 'summary'; }
    elsif ($arg =~ /^-dump/)    { $format= 'dump'; }
    else
    {
      &usage;
      exit (0);
    }
    next;
  }

  push (@JOBS, $arg);
}

foreach $job (@JOBS)
{
  if ($format eq '2') { &print_gdb_2 ($job); }
  elsif ($format eq 'dump') { &print_gdb_dump ($job); }
  elsif ($format eq 'summary') { &print_gdb_summary ($job); }
  else { &print_gdb ($job); }
}

# cleanup

exit (0);

# ----------------------------------------------------------------------------
sub usage
{
  print <<END_OF_USAGE
usage: $0 [-options] [filenanme]

Options:
-help                   ... print help
-dbdef                  ... dump database definition
-noh                    ... hide header
-nonotes                ... hide the notes records
-format <name>          ... dump data in format
-dump                   ... dump everything in printable form
-sum)ary                ... write only a summary line abut each DB

-format 2               Full Export Format (to be completed)
missing items:
  cardpage
  db_header

T2D (format 2):
  option: show names of empty fields
END_OF_USAGE
}

# ----------------------------------------------------------------------------
sub print_gdb
{
  my $view= '';  # retrieve a view description
  my $fnm= shift;

  my (@data, $i);
  my %hide;             # hidden fields

  my $db= HP200LX::DB::openDB ($fnm);

  if ($show_db_def)
  {
      print "database definition:\n:"; $db->show_db_def (*STDOUT);
    # print "card definition:\n:";     $db->show_card_def (*STDOUT);
    $db->dump_def (*STDOUT);
  }

  my $db_cnt= $db->get_last_index ();
  tie (@data, HP200LX::DB, $db);

  for ($i= 0; $i <= $db_cnt; $i++)
  {
    my $rec= $data[$i];
    my $fld;

    if ($i == 0)
    { # when the first record is processed, print header and find notes
      foreach $fld (sort keys %$rec)
      {
        if (!$show_notes && $fld =~ /(.+)\&/)
        {
          $hide{$1}++;
          $hide{$fld}++;
        }
      }
      foreach $fld (sort keys %$rec)
      {
        print $fld, $FS if ($show_fields && !defined ($hide{$fld}));
      }

      print $RS if ($show_fields);
      $show_fields= 0;
    }

    foreach $fld (sort keys %$rec)
    {
      next if (defined ($hide{$fld}));
      print $rec->{$fld}, $FS;
    }
    print $RS;
  }

}

# ----------------------------------------------------------------------------
sub print_gdb_summary
{
  my $fnm= shift;

  my (@data, $i);

  my $db= HP200LX::DB::openDB ($fnm, undef, 1); # no decryption
  $db->print_summary ($print_header);
  $print_header= 0;
}

# ----------------------------------------------------------------------------
sub print_gdb_dump
{
  my $fnm_db= shift;
  my $fnm_out= shift;
  local *FO;

  if (defined ($fnm_out))
  {
    unless (open (FO, ">$fnm_out"))
    {
      print STDERR "can't write to $fnm_out\n";
    }
  }
  else { *FO= *STDOUT; }

  my $db= HP200LX::DB::openDB ($fnm_db, undef, 1);

  $db->dump_type (*FO);

  close (FO) if (defined ($fnm_out));
}

# ----------------------------------------------------------------------------
sub print_gdb_2
{
  my $fnm= shift;

  my (@data, $i);

  my $db= HP200LX::DB::openDB ($fnm);

  if ($show_db_def)
  {
      print "database definition:\n"; $db->show_db_def (*STDOUT);
    $db->show_card_def (*STDOUT);

    my $vpt_cnt= $db->get_viewptdef_count;
    for ($i= 0; $i <= $vpt_cnt+100; $i++)
    {
      my $def= $db->find_viewptdef ($i);
      last unless (defined ($def));

      # print ">>> ", join (':', keys %$def), "\n";
      print "&type:vpt\n";
      print "&idx:$i\n";
      HP200LX::DB::vpt::show_viewptdef ($def, *STDOUT);
    }
  }

  my $db_cnt= $db->get_last_index ();
  tie (@data, HP200LX::DB, $db);

  for ($i= 0; $i <= $db_cnt; $i++)
  {
    my $rec= $data[$i];
    my $fld;

    print "&type:data\n";
    print "&idx:$i\n";
    foreach $fld (sort keys %$rec)
    {
      my $val= $rec->{$fld};
      # print $fld, '=', $val, "\n" if ($val);
      print_content_line (*STDOUT, $fld, $val, 'rfc', 0) if ($val);
    }
    print "\n";
  }
}

