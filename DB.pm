#
# FILE %gg/perl/HP200LX/DB.pm
#
# access HP 200LX database files
# See POD Section for a few more details
#
# work area: decode_type14
#
# written:       1997-12-28 (c) g.gonter@ieee.org
# latest update: 1999-02-22 20:46:39
#

package HP200LX::DB;

use strict;
use vars qw($VERSION @ISA @EXPORT_OK);
use Exporter;

$VERSION = '0.06';
@ISA = qw(Exporter);
@EXPORT_OK= qw(openDB saveDB);

use HP200LX::DB::vpt;     # view point management, including vpt definition

# ----------------------------------------------------------------------------
my $no_note= 65535;             # note number if there is no note
my $no_val=  65535;             # NIL, empty list, -1 etc.
my $no_time= 32768;             # empty time field
my $no_year=   255;             # empty year, mon, day elements
my $no_mon=    255;
my $no_day=    255;
my $no_date=   255;             # ... no_date values
my $delim= '-'x 74;             # optic delimiter

# ----------------------------------------------------------------------------
my @REC_TYPE=           # HP's internal record type definitions
(
  'DBHEADER',           # 0
  'PASSWORD',           # 1: only present when a password was set
  '',                   # 2
  '',                   # 3
  'CARDDEF',            # 4
  'CATEGORY',           # 5
  'FIELDDEF',           # 6
  'VIEWPTDEF',          # 7 sort and subset
  '',                   # 8
  'NOTE',               # 9
  'VIEWPTTABLE',        # 10 table of viewpoint entries
  'DATA',               # 11
  'LINKDEF',            # 12: usually smart clips
  'CARDPAGEDEF',        # 13
  '',                   # 14 APP:
                        #    + ADB: appt_info
  'SMART_CLIP',         # 15 APP: smart clip def in appt.adb (GG)
                        #    + ADB: appt_list (adbio)
  '',                   # 16 APP
  '',                   # 17 APP
  '',                   # 18 APP
  '',                   # 19 APP
  '',                   # 20 APP
  '',                   # 21 APP
  '',                   # 22 APP
  '',                   # 23 APP
  '',                   # 24 APP
  '',                   # 25 APP
  '',                   # 26 APP
  '',                   # 27 APP
  '',                   # 28 APP
  '',                   # 29 APP
  '',                   # 30 APP
  'LOOKUPTABLE'         # 31
# 14..30 application specific!
);
sub REC_TYPE { my $num= shift; $REC_TYPE[$num] || "USER_TYPE_$num"; }

# ----------------------------------------------------------------------------
my @FIELD_TYPE=            # HP's internal field type definitions
(
  { 'Desc' => 'BYTEBOOL',     'Size' => 1, },      #  0
  { 'Desc' => 'WORDBOOL',     'Size' => 2, },      #  1 .. e.g. check box
  { 'Desc' => 'STRING',       'Size' => 2, },      #  2
  { 'Desc' => 'PHONE',        'Size' => 2, },      #  3
  { 'Desc' => 'NUMBER',       'Size' => 2, },      #  4
  { 'Desc' => 'CURRENCY',     'Size' => 2, },      #  5
  { 'Desc' => 'CATEGORY',     'Size' => 2, },      #  6
  { 'Desc' => 'TIME',         'Size' => 2, },      #  7     Test: store
  { 'Desc' => 'DATE',         'Size' => 3, },      #  8     Test: store
  { 'Desc' => 'RADIO_BUTTON', 'Size' => 1, },      #  9     Note: 1 byte, may be 2?
  { 'Desc' => 'NOTE',         'Size' => 2, },      # 10     Store: seems to work now
  { 'Desc' => 'GROUP',        'Size' => 0, },      # 11
  { 'Desc' => 'STATIC',       'Size' => 0, },      # 12: Label
  { 'Desc' => 'MULTILINE',    'Size' => 0, },      # 13 ??
  { 'Desc' => 'LIST',         'Size' => 0, },      # 14
  { 'Desc' => 'COMBO',        'Size' => 0, },      # 15
  { 'Desc' => 'U16',          'Size' => 0, },      # 16: WDB time zone difference
  { 'Desc' => 'U17',          'Size' => 0, },      # 17
  { 'Desc' => 'U18',          'Size' => 1, },      # 18: ADB "Repeat Status"
  { 'Desc' => 'U19',          'Size' => 3, },      # 19: ADB "Start Date"
  { 'Desc' => 'U20',          'Size' => 2, },      # 20: ADB "Due Date"
  { 'Desc' => 'U21',          'Size' => 0, },      # 21
  { 'Desc' => 'U22',          'Size' => 2, },      # 22: ADB "Priority"
  { 'Desc' => 'U23',          'Size' => 2, },      # 23: ADB "#consecutive days"
  { 'Desc' => 'U24',          'Size' => 2, },      # 24: ADB "Leadtime"
  { 'Desc' => 'U25',          'Size' => 0, },      # 25
);

# ----------------------------------------------------------------------------
my @PRE_CODE=
( # so called secret key... (checked againsthpcrack.c)
  0xE1, 0xA8, 0xF7, 0x14, 0x0B, 0xC5, 0x49, 0x42,       # 0x00
  0xAC, 0x73, 0xFA, 0xA9, 0x78, 0xDD, 0x48, 0x6D,       # 0x08
# The rest is pure guesswork ... (1998-01-03 12:10:50)
  0x71, 0x33, 0x50, 0x8E, 0xDD, 0x9C, 0x83, 0x5B,       # 0x10
  0xAD, 0xDF, 0x28, 0xBA, 0xC0, 0xC8, 0xA5, 0xF3,       # 0x18
  0x26, 0xA5, 0xE1, 0xE7, 0x2F, 0x1C, 0x2C, 0xD7,       # 0x20
  0x0A, 0xA3, 0x9C, 0x34, 0xCC, 0x59, 0xF2, 0x7F,       # 0x28
  0x1D, 0x4A, 0xDD, 0xFF, 0xDE, 0x16, 0xA9, 0x4E,       # 0x30
  0xC0, 0x92, 0x5C, 0xA8, 0x09, 0x2F, 0xDD, 0x1D,       # 0x38
  0xD9, 0x97, 0x75, 0x0D, 0x32, 0x7B, 0x5E, 0x9E,       # 0x40
  0xC0, 0x3C, 0x6C, 0xDA, 0xDF, 0x06, 0x41, 0xDE,       # 0x48
  0xC2, 0x40, 0xCD, 0xAC, 0x9C, 0x56, 0xCF, 0x6A,       # 0x50
  0x3E, 0xD7, 0xE3, 0x08
);
my @PRE_PADDING=
( # padding data used to strip away the remainder of the password
  0xFF, 0x13, 0x72, 0x4F, 0x7F, 0x22, 0x40, 0x37,       # 0x00
  0x7E, 0x18, 0x65, 0x2D, 0x55, 0x47, 0x77, 0x68,       # 0x08
);

# ----------------------------------------------------------------------------
my %XHDR=       # debugging: headers that will not be printed
(
  'sig' => 1, 'time' => 1, 'lookup_table_offset' => 1, 'recheader' => 1,
);

# ----------------------------------------------------------------------------
# create a new (empty) database object
sub new
{
  my $fnm= shift;
  my $apt= shift || &derive_apt ($fnm);

  # print ">>> NEW: fnm='$fnm' apt='$apt'\n";
  my $i;
  my $Types= [];
  my @t= localtime (time);

  for ($i= 0; $i < 32; $i++) { push (@$Types, []); }

  my $obj=
  {
    'Filename'  => $fnm,

    'APT'       => $apt,                # application type
                                        # GDB: generic database (default)
                                        # NDB: note taker (NDB == GDB)
                                        # ADB: appointment book
                                        # WDB: world time
    'APT_Data'  => {},                  # application specific extension data

    'Header'    =>
    {
      'sig'       => "hcD\000",
      'recheader' =>
      {
        'type'      => 0,
        'status'    => 0,
        'length'    => 19,
        'idx'       => 0,
      },

      'time'      =>
      {
        'year'      => $t[5],
        'mon'       => $t[4]+1,
        'day'       => $t[3],
        'min'       => $t[2]*60 + $t[1],
      },

      # guessed data from other examples
      'file_status'     => 0,
      'file_type'       => 68,
      'release_version' => 258,
      'viewpt_hash'     => 34085,
    },

    'Types' => $Types,          # DB records of each type

    # pre-processed internal datatypes
    'fielddef'          => [],  # data descriptions of fields
    'carddef'           => [],  # window descriptions of fields
    'cardpagedef'       => [],  # description for the four cards
    'viewptdef'         => [],  # view point definitins; list/sort/filter
    'viewpttable'       => [],  # cached view point table
  };

  bless $obj;
}

# ----------------------------------------------------------------------------
sub derive_apt
{
  my $fnm= shift;
  my $APT= 'GDB';       # generic database

     if ($fnm =~ m/\.adb$/i) { $APT= 'ADB'; }   # appointment book
  elsif ($fnm =~ m/\.ndb$/i) { $APT= 'NDB'; }   # note taker
  elsif ($fnm =~ m/\.wdb$/i) { $APT= 'WDB'; }   # world time application
  # else: gdb, pdb: GDB  (generic data base)

  $APT;
}

# ----------------------------------------------------------------------------
# open a given file and read the database into memory
sub openDB
{
  my $fnm= shift;
  my $APT= shift;
  my $obj= new ($fnm, $APT);
  $APT= $obj->{APT};  # use application detection logic in new
  my $b;
  my $sig;
  local (*FI);

  unless (open (FI, $fnm))
  {
    print "ERROR: could not open DB file '$fnm'!\n";
    return undef;
  }
  binmode (FI); # MS-DOS systems need this, T2D: how about Mac?

  read (FI, $sig, 4);

  # BEGIN to read the record header
  my $recheader= &get_recheader (*FI);
  my $lng= $recheader->{'length'};
  print "WARNING lng=$lng, 25 expected!\n" unless ($lng == 25);

  read (FI, $b, 19);  # lng minus length of record header: 19+6= 25
  my ($release_version, $file_type, $file_status,
      $cur_viewpt, $num_recs, $lookup_table_offset,
      $year, $mon, $day, $min, $viewpt_hash)= unpack ('vCCvvVCCCvv', $b);
  # END to read the record header

  my $time=
  {
    'year'      => $year,
    'mon'       => $mon,
    'day'       => $day,
    'min'       => $min,
  };

  my $hdr=
  {
    'sig'       => $sig,
    'time'      => $time,
    'recheader' => $recheader,

    'release_version'   => $release_version,
    'file_type'         => $file_type,
    'file_status'       => $file_status,
    'cur_viewpt'        => $cur_viewpt,
    'num_recs'          => $num_recs,
    'lookup_table_offset' => $lookup_table_offset,
    'viewpt_hash'       => $viewpt_hash,
  };

  $obj->{Header}= $hdr;

  # read lookup table
  my ($v, $i);
  my $ltbl= [];
  my $ftbl= [];

  seek (FI, $lookup_table_offset, 0);
  my $xrec= &get_recheader (*FI);
  # &print_recheader (*STDOUT, "lookup table:", $xrec);
  $lng= $xrec->{'length'}-6;
  $i= read (FI, $b, $lng);

  print "WARNING: could not read complete lookup table; read=$i lng=$lng\n"
    unless ($i == $lng);

  $i= $num_recs * 8; # 8 byte per lookup table entry
  print "WARNING: lookup table size seems wrong;",
        " lng=$lng num_recs=$num_recs $num_recs*8=$i\n"
     unless ($i == $lng);

  for ($i= 0; $i < $num_recs; $i++)
  {
    my ($size, $filters, $flags, $off_low, $off)=
      unpack ('vvCCv', substr ($b, $i*8, 8));
    $off= $off*256+$off_low;

    # print "lut [$i] off=$off size=$size\n";
    my $lut=
    {
      'siz'     => $size,
      'off'     => $off,
      'filters' => $filters,
      'flags'   => $flags,
    } ;

    push (@$ltbl, $lut);
  }
  
  # $hdr->{lookup_table_header}= $xrec;
  # $hdr->{lookup_table}= $ltbl;

  # typefirst table
  #
  # Purpose:
  #   This table points into the lookup table at the position of the
  #   first record of each record type
  # Example:
  #   lookup data for record 3 of type 4 is at: ltbl [ftbl [4] + 3]
  # NOTE:
  #   this is not used here!
  #
  # printf ("typefirst table: 0x%08lX\n", $lookup_table_offset + $lng + 6);
  $i= read (FI, $b, 64);
  print "WARNING: could not read complete typefirst table; read=$i lng=64\n"
    unless ($i == 64);
  for ($i= 0; $i < 32; $i++)
  {
    $v= unpack ('v', substr ($b, $i*2, 2));
    push (@$ftbl, $v);
  }
  # $hdr->{typefirst_table}= $ftbl;

  $obj->{Meta}= 'Plaintext';
  my ($CODE, $CODE_SIZE);       # used to decrypt data records
  my $lut;                      # analyzed lut entry
  $i= 0;
  foreach $lut (@$ltbl)
  {
    my $off= $lut->{off};
    my $siz= $lut->{siz} - 6;

    $i++;
    if ($siz < 0 || $off < 0)
    { # empty record
      # print "[$i] type=???? siz=$siz off=$off\n";
      next;
    }

    seek (FI, $off, 0);
    $xrec= &get_recheader (*FI);

    my $type= $xrec->{type};
    # next if ($type == 0);

    if ($type < 0 || $type >= 32)
    {
      print "WARNING: unknown type: $type; IGNORED\n";
      &print_recheader (*STDOUT, "record [$i]:", $xrec);
      next;
    }

    # the real record data!
    read (FI, $b, $siz);

    if ($type > 1 && $obj->{Meta} eq 'Encrypted')
    { # NOTE: currently only decrypts parts of the data correctly!
      my $kk;
      print '-'x72, "\nencoded [type=$type, $REC_TYPE[$type]]\n";
      # print "session key=";
      # foreach $kk (@{$obj->{CODE}}) { printf (" 0x%02X", $kk); }
      # print "\n";
      # &hex_dump ($b);

      $b= &decode ($b, $siz, $obj->{CODE}, 0);

      print "decoded\n";
      &hex_dump ($b);
    }

    $xrec->{data}= $b;

    # additional record data from the LUT
    $xrec->{off}= $off;
    $xrec->{flags}= $lut->{flags};
    $xrec->{filters}= $lut->{filters};

    if ($type == 1)
    { # password record
      $obj->{Meta}= 'Encrypted';

      # decode and print the password
      my $pass= &decode_password ($b, $siz);
      $obj->{Password}= $pass;

      # setup session key (works only for the first 17 bytes!
      my @SESSION_KEY= split (/|/, substr ($b, 0, length ($pass)));
      my $kk;
      foreach $kk (@SESSION_KEY) { $kk= unpack ('C', $kk); }
      # push (@SESSION_KEY, @PRE_PADDING[length($pass)..15]);
      print "session key length: $#SESSION_KEY\n";
      $obj->{CODE}= \@SESSION_KEY;

      if (1 && open (FK, 'key.bin'))
      {
        binmode (FK);    # MS-DOS systems need this, how about the Mac?

        my $key;
        my $key_size= 512; # up to 21400 byte
        read (FK, $key, $key_size);
        close (FK);
        for ($kk= length($pass); $kk < $key_size ; $kk++)
        { $obj->{CODE}[$kk]= unpack ('C', substr ($key, $kk, 1)); }
        for ($kk= 17; $kk < $key_size; $kk += 17)
        {
          $obj->{CODE}[$kk+0] ^= 0x4A;  # p^78
          $obj->{CODE}[$kk+1] ^= 0x27;  #  ^13
          $obj->{CODE}[$kk+2] ^= 0x40;  #  ^72
          $obj->{CODE}[$kk+3] ^= 0x7E;  #  ^4f
          $obj->{CODE}[$kk+4] ^= 0x4B;  #  ^7f
        }
      }

    } # type == 1, password

    elsif ($type == 4) # CARDDEF
    { # only one record of this type allowed!!
      $obj->{carddef}= &get_carddef ($b);
    }

    elsif ($type == 6) # FIELDDEF
    {
      my ($fdef, $rec_size)= &get_fielddef ($b);
      push (@{$obj->{fielddef}}, $fdef);
      $obj->{rec_size}= $rec_size if ($rec_size > $obj->{rec_size});
    }

    elsif ($type == 7) # VIEWPTDEF
    {
      my $vptd= &get_viewptdef ($b);
      push (@{$obj->{viewptdef}}, $vptd);
      $vptd->{index}= $#{$obj->{viewptdef}};
    }

    elsif ($type == 9) # NOTE
    { # note records may be missing, but they are accessed according
      # to their index, thus leave the blank entries in the table.
      $obj->{Types}->[9]->[$xrec->{idx}]= $xrec;
      next;
    }

    elsif ($type == 10) # VIEWPTTABLE
    {
      push (@{$obj->{viewpttable}}, &get_viewpttable ($b));
    }

    elsif ($type == 13) # CARDPAGEDEF
    { # only none or one record of this type allowed!!
      $obj->{cardpagedef}= &get_cardpagedef ($b);
    }

    unless ($REC_TYPE[$type])
    { # application specific data
      if ($type == 14 && $APT eq 'ADB')
      {
        $obj->decode_type14 (*STDOUT, $b);
      }
      else
      { # dump info about other unknown field types
        print "[$i] off=$off siz=$siz type=$type APT='$APT'\n";
        &print_recheader (*STDOUT, "record [$i]:", $xrec);

        # print "b='$b'\n";
        &hex_dump ($b);
      }
    }

    push (@{$obj->{Types}->[$type]}, $xrec);
  }
  # print "LUT table size: i=$i\n";

  close (FI);

  $obj;
}

# ----------------------------------------------------------------------------
sub saveDB
{
  my $self= shift;
  my $fnmo= shift || $self->{Filename};

  my $hdr= $self->{Header};
  my $Types= $self->{Types};

  my ($type, $Data, $rec, $lng, $idx);

  # fixup header if necessary
  $Data= $Types->[0];

  my ($off)= 4;
  my (@lut, @ftype, $ftype);   # lookup table and first type table
  my $lut= 0;
  my $num_recs= 0;

  # calculate lookup table and firsttype table
  # . for each record type: calculate size of each entry
  # print "lut_size= $#lut $lut\n";
  for ($type= 0; $type < 32; $type++)
  {
    push (@ftype, $lut);
    $Data= $Types->[$type];

    for ($idx= 0; $idx <= $#$Data; $idx++)
    {
      $rec= $Data->[$idx];

      # print ">>> save: type=$type idx=$idx\n";

      # T2D, TEST: note records may be blank!!
      if (defined ($rec))
      { # populated record to be saved
        $lng= length ($rec->{data});

        $rec->{off}= $off;
        $off += ($rec->{'length'}= $lng + 6);  # 6 off ???
        $rec->{idx}= $idx;

        unless (defined ($rec->{type}))
        { # set type if not alrady done
          $rec->{type}= $type;
        }

        unless (defined ($rec->{status}))
        { # set type if not alrady done
          $rec->{status}= 2; # T2D: status == 2 means what ???
        }
      }
      else
      { # empty record, set up an entry for the lookup table
        print ">>>>> save rec type=$type idx=$idx undefined!\n";

        $rec=
        {
          off     => 0,
          'length'=> 0,
          flags   => 0,
          filters => 0,
        };
      }

      $lut [$lut++]= $rec;
      $num_recs++;
    }
  }

  # print "lut_size= $#lut $lut num_recs=$num_recs off=$off\n";

  $hdr->{lookup_table_offset}= $off;
  $hdr->{num_recs}= $num_recs;

  local (*FO);
  open (FO, ">$fnmo") || die;
  binmode (FI); # MS-DOS systems need this, T2D: how about Mac?

  # save record header
  print FO $hdr->{sig};
  &put_recheader (*FO, $hdr->{recheader});
  my $time= $hdr->{'time'};
  my $b= pack ('vCCvvVCCCvv',
           $hdr->{release_version},
           $hdr->{file_type}, $hdr->{file_status},
           $hdr->{cur_viewpt}, $hdr->{num_recs},
           $off,
           $time->{year}, $time->{mon},
           $time->{day}, $time->{min},
           $hdr->{viewpt_hash},
         );
  print FO $b;

  # save each record for each type
  for ($type= 1; $type < 32; $type++)
  {
    $Data= $Types->[$type];

    for ($idx= 0; $idx <= $#$Data; $idx++)
    {
      $rec= $Data->[$idx];

      next unless (defined ($rec->{data})); # empty records
      # print ">>> save data records type=$type idx=$idx\n";
      &put_recheader (*FO, $rec);
      print FO $rec->{data};
    }
  }

  # print "lut_size= $#lut $lut\n";

  # save lookup table
  $rec=
  {
    'type'      => 31,
    'status'    => 0,
    'length'    => ($#lut+1)*8+6,
    'idx'       => 0,
  };

  &put_recheader (*FO, $rec);
  foreach $lut (@lut)
  {
    my $off_low= $lut->{off}%256;
    my $off= $lut->{off}/256;

    my $b= pack ('vvCCv', 
             $lut->{'length'},
             $lut->{filters}, $lut->{flags},
             $off_low, $off
           );

    print FO $b;
  }

  # save firsttype table
  foreach $ftype (@ftype)
  {
    my $b= pack ('v', $ftype);
    print FO $b;
  }

  close (FO);
}

# ----------------------------------------------------------------------------
sub get_field_def
{
  my $self= shift;
  my $num= shift;

  $self->{fielddef}->[$num];
}

# ----------------------------------------------------------------------------
sub show_db_def
{
  my $self= shift;
  local (*FO)= shift;

  my $Fdef= $self->{fielddef};
  my $field;
  my $num= 0;
  my %off= (); # sorted by offset
  my $off;

  my $hdr= sprintf ("[##] ## %-12s Siz %-24s FID  Off  Res  Flg\n",
                    "Type", "Name");
  print FO $delim, "\n";
  print FO "DB def by field number\n", $hdr;

  foreach $field (@$Fdef)
  {
    $off= &show_field_def (*FO, $field, $num++);
    push (@{$off{$off}}, $field);
  }

  $num= 0;
  print FO $delim, "\n", "DB def by offset position\n", $hdr;
  foreach $off (sort keys %off)
  {
    foreach $field (@{$off{$off}})
    {
      &show_field_def (*FO, $field, $num);
    }
    $num++
  }

  print FO $delim, "\n";
}

# ----------------------------------------------------------------------------
sub show_card_def
{
  my $self= shift;
  local (*FO)= shift;

  my $Cdef= $self->{carddef};
  return if ($#$Cdef < 0);
  my ($field, $f);

  print FO "card definition:\n";
  foreach $field (@$Cdef)
  {
    # &show_field_window ($field);
    print FO "field:";
    foreach $f (sort keys %$field)
    {
      print " $f=$field->{$f},";
    }
    print "\n";
  }
}

# ----------------------------------------------------------------------------
sub dump_data
{
  my $self= shift;

  my $APT= $self->{APT};
  my $T= $self->{Types} || die;
  my $D= $T->[11];  # array of data records
  my $N= $T->[9];   # array of note records

  my $rec_beg= shift || 0;
  my $rec_end= shift || $#$D;
  my $Fdef= shift || $self->{fielddef};  # array of field definitions

  my ($rec, $field);

  print "show_data\n";
  foreach $rec ($rec_beg .. $rec_end)
  {
    my $d= $D->[$rec] || next;
    my $b= $d->{data} || next;

    my ($ok, $o)= &fetch_data ($b, $Fdef, $N, $APT);
    &dump_data_record ($b, $ok, $o);
  }
}

# ----------------------------------------------------------------------------
sub TIEARRAY
{
  return $_[1];
}

# ----------------------------------------------------------------------------
sub FETCH_raw
{
  my $db= shift;
  my $idx= shift;

  my $T= $db->{Types} || return undef;
  my $D= $T->[11];      # array of data records
  return undef if ($idx > $#$D);

  $D->[$idx]->{data};   # data record for the given index
}

# ----------------------------------------------------------------------------
sub FETCH
{
  my $db= shift;
  my $idx= shift;

  my $T= $db->{Types} || die 'not a database';
  my $D= $T->[11];      # array of data records
  return undef if ($idx > $#$D);

  my $Dx= $D->[$idx];   # data record for the given index
  my $rv;

  unless (defined ($rv= $Dx->{obj}))
  { # no record data was previously stored, fetch that
    my $N= $T->[9];   # array of note records
    my $F= $db->{fielddef};
    my $b= $Dx->{data};
    my $APT= $db->{APT};

    # print "FETCH: T=$T D=$D N=$N F=$F b=$b\n";
    my ($ok, $o)= &fetch_data ($b, $F, $N, $APT);
    # &dump_data_record ($b, $ok, $o);

    $Dx->{obj}= $rv= $o;
    $Dx->{ok}= $ok;
  }

  return $rv;
}

# ----------------------------------------------------------------------------
sub STORE
{
  my $db= shift;
  my $idx= shift;
  my $val= shift;

  my $T= $db->{Types} || die;
  my $D= $T->[11];  # array of data records
  my $N= $T->[9];   # array of note records
  my $F= $db->{fielddef};
  my $APT= $db->{APT};

  my $Dx;

  if ($idx > $#$D)
  {
    # print "adding records: num=$#$D idx=$idx\n";
    $Dx= { 'data' => '' };
  }
  else
  {
    $Dx= $D->[$idx];   # data record for the given index
  }

  my ($ok, $b)= &store_data ($val, $F, $N, $APT, $db->{rec_size});

  $Dx->{data}= $b;
  undef ($Dx->{obj});
  undef ($Dx->{ok});
  $D->[$idx]= $Dx;

  # T2D: unfinished
  # missing items: refreshing and/or invalidating view points
}

# ----------------------------------------------------------------------------
sub get_last_index
{
  my $db= shift;

  my $T= $db->{Types} || die;
  my $D= $T->[11];      # array of data records
  return $#$D;
}

# ----------------------------------------------------------------------------
sub get_str
{
  my $b= shift;
  my $off= shift;

  my $res= substr ($$b, $off);
  my $idx= index ($res, "\000");
  $res= substr ($res, 0, $idx) if ($idx >= 0);
  $res;
}

# ----------------------------------------------------------------------------
sub fmt_date
{
  my $str= shift;

  my ($year, $mon, $day)= unpack ('CCC', $str);
  ($year == $no_year && $mon == $no_mon && $day == $no_day)
  ? '' # empty date field
  : sprintf ("%d-%02d-%02d", 1900 + $year, $mon+1, $day+1);
}

# ----------------------------------------------------------------------------
sub fmt_time
{
  my $str= shift;

  my $val= unpack ('v', $str);
  return '' if ($val == $no_time || $val == $no_val);

  my $min= $val % 60;
  my $xval= int ($val / 60);
  sprintf ("%d:%02d", $xval, $min);
}

# ----------------------------------------------------------------------------
sub fetch_data
{
  my $b=        shift;  # raw binary data
  my $Fdef=     shift;  # Field Definitions
  my $N=        shift;  # Notes Data
  my $APT=      shift;  # application type

  my $ok= 1;
  my %o;
  my %RB;     # radio button at offset
  my $field;

  my @Fdef= @$Fdef;     # Field Definition List
  my $APT2;

  if ($APT eq 'ADB')
  { # For appointment book entries we have to analyze if
    # the record describes a to-do item or a date or event

    my $val= unpack ('C', substr ($b, 0x0E, 1));
    my @TLT= ();

    #  if ($val & 0x02) { $APT2= 'Done'; } # checked to-do entry
       if ($val & 0x10) { $APT2= 'To-Do'; @TLT= (0, 1, 8..12); }
    elsif ($val & 0x20) { $APT2= 'Event'; @TLT= (0..7, 12, 14, 15); }
    elsif ($val & 0x80) { $APT2= 'Date';  @TLT= (0..7, 12, 14, 15); }

    $o{'type'}= $APT2;
    $o{'repeat'}= unpack ('C', substr ($b, 0x1A, 1));

    @Fdef= map { $Fdef[$_] } @TLT;
  }

  FIELD: foreach $field (@Fdef)
  {
    my $type= $field->{ftype};
    my $off=  $field->{off};
    my $name= $field->{name};
    my $res;
    # printf ("APT= 0x%02X %2d '%s'\n", $off, $type, $name);

      if ($type == 0) # BYTE_BOOL
      {
        my $val= unpack ('C', substr ($b, $off, 1));
        $res= ($val) ? 'X' : '';
      }
      elsif ($type == 1) # WORD_BOOL
      {
        my $val= unpack ('v', substr ($b, $off, 2));
        $res= ($val) ? 'X' : '';
      }
      elsif ($type == 2 && $APT eq 'ADB' && $off eq 0x1B)
      { # Beschreibung bei ADB geht ohne Offset!
        $res= &get_str (\$b, $off);
      }
      elsif ($type == 2         # STRING
             || $type == 3      # PHONE
             || $type == 4      # NUMBER
             || $type == 6      # CATEGORY
            )
      {
        my $offs= unpack ('v', substr ($b, $off, 2));
        $res= &get_str (\$b, $offs);
      }
      elsif ($type == 7  # TIME
             || ($type == 24 && $APT eq 'ADB') # Vorlauf
            )
      {
        #??? next if ($APT eq 'APT' && $APT2 eq 'To-Do'); # overlapping fields
        $res= &fmt_time (substr ($b, $off, 2));
      }
      elsif ($type == 8 # DATE
             || ($type == 19 && $APT eq 'ADB') # Beginndatum
            )
      {
        $res= &fmt_date (substr ($b, $off, 3));
      }
      elsif ($type == 9) # RADIO_BUTTON
      {
        my $val= unpack ('C', substr ($b, $off, 1));  # 2 or 1 byte??
        my $cnt= ++$RB{$off};
        $res= ($cnt == $val) ? 'X' : '';
      }
      elsif ($type == 10) # NOTE
      {
        my $note_number= unpack ('v', substr ($b, $off, 2));
        $o{"$name&nr"}= $note_number;
        unless ($note_number eq $no_note)
        {
          my $nr;
          $nr= $N->[$note_number];    # $nr should be a valid reference!
          $res= (defined ($nr)) ? $nr->{data} : '';
        }
      }
      elsif ($type == 11        # GROUP
             || $type == 12     # STATIC (e.g. Label)
             || $type == 14     # LIST
             || $type == 15     # COMBO
             || ($type == 18 && $APT eq 'ADB') # repeat factor
            ) # no action ?!?!?
      {
        next FIELD;
      }
      elsif ($type == 16 && $APT == 'WDB')
      {
        $res= unpack ('v', substr ($b, $off, 2));
      }
      elsif ($APT eq 'ADB'
             && ($type == 23    # number of days
                 || $type == 20 # date due Faelligkeitsdatum
                )
            )
      {
        next if ($type == 23 && $APT2 eq 'To-Do');
        next if ($type == 20 && $APT2 ne 'To-Do');

        $res= unpack ('v', substr ($b, $off, 2)); # 2 byte integer value
      }
      elsif ($APT eq 'ADB' && $type == 22)
      {
        # print "\n", $delim, "\n>>> U22: APT2='$APT2'\n";
        next unless ($APT2 eq 'To-Do'); # priority code
        $res= substr ($b, $off, 2);
        $res=~ s/\x00//g;
      }
      else
      {
        $res= "unknown type $type";
        &show_field_def (*STDOUT, $field, -1);
        $ok= 0;
      }

    # print "fetch: name=$name res=$res\n";
    $o{$name}= $res;
  }

  return ($ok, \%o);
}

# ----------------------------------------------------------------------------
sub store_data
{
  my $data= shift;      # record data to be stored into the database
  my $Fdef= shift;      # Field Definitions
  my $N= shift;         # Notes Data; array of references
  my $APT= shift;       # application type
  my $rec_size= shift;  # standard record size and next string position

  my $b_off= 0;         # offset into binary data
  my @b=                # binary data at each offset
  my $b;                # final binary data
  my $nil_addr;         # address of the NIL string record
                        # this is set up when there are actually strings
                        # see notes below

  my $ok= 1;
  my %RB;
  my $field;

  # print "rec_size= $rec_size\n";

  FIELD: foreach $field (@$Fdef)
  {
    my $type= $field->{ftype};
    my $off=  $field->{off};
    my $name= $field->{name};
    my $ex=   (exists ($data->{$name})) ? 1 : 0;        # data value present?
    my $val=  $data->{$name};                           # actual value
    my $APT2;

    $APT2= $data->{type} if ($APT eq 'ADB');

    # print "offset= $off name=$name val=$val\n";

      if ($type == 0)           # BYTEBOOL
      {
        $b [$off]= pack ('C', ($val) ? 1 : 0);
      }
      elsif ($type == 1)        # WORDBOOL
      {
        $b [$off]= pack ('v', ($val) ? 1 : 0);
      }
      elsif ($type == 2         # STRING
             || $type == 3      # PHONE
             || $type == 4      # NUMBER
             || $type == 6      # CATEGORY
            )
      {
        if ($nil_addr eq '')
        { # create empty string which is used for all other empty strings
          # see note below
          $nil_addr= $rec_size;
          $b [$rec_size++]= "\000";
        }

        if ($val)
        {
          $b [$off] = pack ('v', $rec_size);
          $b [$rec_size]= $val . "\000";
          $rec_size += length ($val) + 1;
        }
        else
        { # store pointer to the empty string record
          $b [$off] = pack ('v', $nil_addr);
        }
      }
      elsif ($type == 7)         # TIME
      {
        next if ($APT eq 'ADB' && $APT2 eq 'To-Do');

        my ($h, $m, $t);
        $h= $val;
        ($h, $m)= ($1, $2) if ($val =~ /(\d+):(\d+)/);
        $t= $h*60+$m;
        $t= $no_time if (!$ex || $t < 0 || $t > $no_time);
        $b [$off]= pack ('v', $t);
      }
      elsif ($type == 8)        # DATE
      {
        my ($year, $mon, $day);

        $year= $mon= $day= $no_date;
        if ($ex && $val =~ /(\d+)-(\d+)-(\d+)/)
        {
          ($year, $mon, $day)= ($1, $2, $3);
          # check for valid dates otherwise set no_date value
          $year= $mon= $day= $no_date
            if ($year < 1900 || $year > 2155
                || $mon < 1 || $mon > 12
                || $day < 1 || $day > 31);
          $year -= 1900;
          $mon--; $day--;
        }

        $b [$off]= pack ('CCC', $year, $mon, $day);
      }
      elsif ($type == 9)        # RADIO_BUTTON
      { # several radio buttons point to the same offset
        # the value can be the number of the button pointing there
        # or 0 when no button is checked

        my $v;                       # value to be stored
        my $checked= ($val) ? 1 : 0;
        $checked= 0 if ($v= $RB{$off});     # only the first button is valid
        $RB{$off}= $v= $field->{res} if ($checked);

        $b [$off]= pack ('C', $v);
      }
      elsif ($type == 10)       # NOTE
      { # store note record

        # possible cases:
        # stored | new | action
        #     no |  no | no action, $no_note is already stored
        #     no | yes | store new note number
        #    yes |  no | T2D: delete old note, but how??
        #    yes | yes | store note number and replace the note

        my $note_nr= $no_note;
        my $xn= "$name&nr";
        $note_nr= $data->{$xn} if (defined ($data->{$xn}));  # stored note

        if ($note_nr == $no_note && $val ne '')
        { # no note before but a valid note: create new note record
          push (@$N, { data => $val });
          $data->{$xn}= $note_nr= $#$N;
        }
        elsif ($note_nr != $no_note && $val eq '')
        { # T2D: delete note!!
          # this leaves an empty note record in the database !!!
          undef ($N->[$note_nr]->{data}); # T2D, Test
          $data->{$xn}= $note_nr= $no_note;
        }
        elsif ($note_nr != $no_note && $val ne '')
        { # replace existing note
          $N->[$note_nr]->{data}= $val;
        }

        $b [$off]= pack ('v', $note_nr);
      }
      elsif ($type == 11        # GROUP
             || $type == 12     # STATIC
             || $type == 14     # LIST
             || $type == 15     # COMBO
            ) # no action ?!?!?
      {
        next FIELD;
      }
      else
      {
        print "store_data: ERROR! unknown type $type\n";
        &show_field_def (*STDOUT, $field, -1);
        print "value: $val\n";
        $ok= 0;
      }
  }

  if ($ok)
  {
    $b= join ('', @b);

    if (length ($b) != $rec_size)
    {
      print "ERROR: resulting record size does not match!\n",
            "length=", length ($b), " rec_size=$rec_size\n";
      my ($x, $y);
      for ($x= 0; $x <= $#b; $x++)
      {
        next unless ($y= $b[$x]);
        printf ("[%02d] %2d '%s'\n", $x, length ($y), $y);
      }
    }
  }

  # T2D: unfinished
  return ($ok, $b);
}

# NOTES:
# Empty Strings are stored as null character at the beginning of the
# extended data record.  All empty strings point to the same address.
# An empty string is stored even when all strings have a value.

# ----------------------------------------------------------------------------
# read a 6 byte record header
sub get_recheader
{
  local (*F)= shift;
  my $b;

  read (F, $b, 6) || return undef;
  my ($type, $status, $length, $idx)= unpack ('CCvv', $b);

  my $rec=
  {
    'type'      => $type,
    'status'    => $status,
    'length'    => $length,
    'idx'       => $idx,
  };

  $rec;
}

# ----------------------------------------------------------------------------
# read a 6 byte record header
sub put_recheader
{
  local (*F)= shift;
  my $r= shift;

  my $b= pack ('CCvv', $r->{type}, $r->{status}, $r->{'length'}, $r->{idx});
  print F $b;
}

# ----------------------------------------------------------------------------
sub fmt_time_stamp
{
  my $time= shift;
  my $Time= sprintf ("%d-%02d-%02d %2d:%02d",
                    1900 + $time->{year}, $time->{mon}+1, $time->{day}+1,
                    $time->{min} / 60, $time->{min} % 60);

  $Time;
}

# ----------------------------------------------------------------------------
sub get_carddef
{
  my $def= shift;
  my @wins;
  my $num= 0;

  # print ">>> processing card definition\n";
  while ($def)
  {
    my $pw= substr ($def, 0, 20);
    $def= substr ($def, 20);

    my ($u, $x, $y, $w, $h, $Lsize, $style, $parent)=
       unpack ('VvvvvvVv', $pw);

    # printf ("[%3d] x=%3d y=%3d w=%3d h=%3d L=%3d S=0x%08lX P=0x%04X\n",
    #         $num, $x, $y, $w, $h, $Lsize, $style, $parent);

    $num++;

    my $win=
    {
      'x' => $x,
      'y' => $y,
      'w' => $w,
      'h' => $h,
      'Lsize' => $Lsize,
      'Style' => $style,
      'Parent' => $parent,
    };

    push (@wins, $win);
  }

  \@wins;
}

# ----------------------------------------------------------------------------
sub get_fielddef
{
  my $def= shift;

  my ($ftype, $fid, $off, $flg, $res)= unpack ('CCvCv', $def);
  my $name= substr ($def, 7, length ($def)-8);
  $name=~ s/\&//g;

  my $fd=
  {
    'ftype'     => $ftype,
    'Ftype'     => $FIELD_TYPE [$ftype]->{Desc},
    'fid'       => $fid,
    'off'       => $off,
    'flg'       => $flg,
    'res'       => $res,
    'name'      => $name,
  };

  $off += $FIELD_TYPE [$ftype]->{Size};
  ($fd, $off);
}

# ----------------------------------------------------------------------------
sub get_cardpagedef
{
  my $def= shift;

  # print ">>> processing card page definition\n";
  my @pages;
  my ($PW, $CP, $PC, @ps, @pc, $i);

  ($PW, $CP, $PC,
   $ps[1], $ps[2], $ps[3], $ps[4],
   $pc[1], $pc[2], $pc[3], $pc[4])= unpack ('vvvvvvvvvv', $def);

  # print ">>>> CP=$CP PC=$PC\n";
  for ($i= 1; $i <= $PC; $i++)
  {
    push (@pages, { 'num' => $i, 'start' => $ps[$i], 'size' => $pc[$i] });
    # print ">>>>> [$i] start=$ps[$i] size=$pc[$i]\n";
  }

  \@pages;
}

# ----------------------------------------------------------------------------
sub show_field_def
{
  local *FO= shift;
  my $fdef= shift;
  my $num= shift;

  my $type= $fdef->{'ftype'};
  my $ftype= $FIELD_TYPE[$type];
  my $ttype= $ftype->{Desc} || "USER$type";
  my $x_siz= $ftype->{Size};
  my $x_off= sprintf ('0x%02X', $fdef->{off});
  my $x_flg= sprintf ('0x%02X', $fdef->{flg});
  my $x_name= $fdef->{name};
  $x_name=~ s/[\x80-\xFF]/?/g;

  printf FO "[%02d] %2d %-12s %3s %-24s %3d %s 0x%02X %s\n",
            $num, $type, $ttype, $x_siz, "'$x_name'",
            $fdef->{fid}, $x_off, $fdef->{res}, $x_flg;

  #print FO "<tr><td align=right>$num<td align=middle>&nbsp;<td align=middle>",
  #         "&nbsp;<td align=right>$type<td>$ttype<td align=right>$x_siz",
  #         "<td align=right>$fdef->{fid}<td align=right>$x_off",
  #         "<td align=right>$fdef->{res}<td align=right>$x_flg",
  #         "<td>'$x_name'\n";
  # print FO "<td>'$x_name'\n";
  # print FO "[$num] type= $ttype ($type) name='$fdef->{name}'"
  #          " id=$fdef->{fid} off=$x_off res=$fdef->{res} flg=$x_flg\n";

  $x_off;
}

# ----------------------------------------------------------------------------
sub decode_type14          # analyze application specific field type 14
{
  my $obj= shift;
  local *FO= shift;
  my $b= shift;

  my $AD= $obj->{APT_Data};
  my $lng= length ($b);

  my ($off, $d, $v);
  if (defined ($AD->{View_Table}))
  {
    print <<EOX;
Warning: type 14 in data base appears more than twice.
Please send a sample of your database to the author
    &hex_dump ($b);
EOX
  }
  elsif (defined ($AD->{Header}))
  {
    my @View_Table;
    for ($off= 0; $off+5 <= $lng; $off += 5)
    {
      $d= &fmt_date (substr ($b, $off, 3));
      $v= unpack ('v', substr ($b, $off+3, 2));
      last if ($v eq $no_val);  # end marker
      push (@View_Table, { 'date' => $d, num => $v } );
      # print FO "    date=$d num=$v\n";
    }
    $AD->{View_Table}= \@View_Table;
    # &hex_dump ($b);
  }
  else
  {
    $d= &fmt_date (substr ($b, 0, 3));
    $AD->{Head_Date}= $d;
    $AD->{Header}= $b;
  }
}

# ----------------------------------------------------------------------------
sub print_recheader
{
  local *FH= shift;
  my $txt= shift;
  my $r= shift;

  my @extra= @_;
  my $fld;
  my $type= $r->{'type'};
  my $ttype= $REC_TYPE[$type] || "USER$type";

  print "$txt\n";

  print "  type= $ttype ($type)\n";
  foreach $fld ('status', 'length', 'idx', @extra)
  {
    print "  $fld= $r->{$fld}\n";
  }
}

# ----------------------------------------------------------------------------
sub dump_def
{
  my $self= shift;
  local (*FO)= shift;
  my $level= shift;

  my $hdr= $self->{Header};
  my $Time= &fmt_time_stamp ($hdr->{'time'});

  my $fld;
  my $sig= substr ($hdr->{sig}, 0, 3);
  my $x_ltable= sprintf ("0x%08lX", $hdr->{lookup_table_offset});

  print FO <<EOX;
Filename: $self->{Filename}
Meta: $self->{Meta}
DB Header:
  sig= $sig
  time= $Time
  lookup_table_offset= $x_ltable
EOX

  foreach $fld (sort keys %$hdr)
  {
    print FO "  $fld= $hdr->{$fld}\n" unless (defined ($XHDR{$fld}));
  }

  &print_recheader (*FO, 'record header:', $hdr->{recheader});
  # print FO 'self:: ', join (',', sort keys %$self), "\n";

  $level= 0 if ($self->{Meta} eq 'Encrypted' && $level < 10);

  if ($level > 0)
  {
    $self->show_db_def (*FO);
    # $self-> show_card_def (*FO);
  }

  if ($level > 1)
  {
    print FO $delim, "\n\n";
    for ($fld= 0; $fld < 32; $fld++)
    {
      $self->dump_db (*FO, $fld);
    }
  }
}

# ----------------------------------------------------------------------------
sub dump_db
{
  my $self= shift;
  local (*FO)= shift;
  my $type= shift;
  my $idx= shift;

  my $Types= $self->{Types};
  my $Data= $Types->[$type];
  my ($el, $i);

  if (defined ($idx))
  {
    $el= $Data->[$idx];
    &dump_db_rec (*FO, $idx, $el);
    return;
  }

  $idx= 0;
  foreach $el (@$Data)
  {
    &dump_db_rec (*FO, $idx, $el);
    $idx++;
  }
}

# ----------------------------------------------------------------------------
sub dump_db_rec
{
  local *FO= shift;
  my $i= shift;
  my $el= shift;

    unless (defined ($el))
    {
      print FO "data record [$i] not defined!\n";
      return;
    }

    &print_recheader (*FO, "data record [$i]", $el, 'filters', 'flags');
    # print FO "el= ", join (':', keys %$el), "\n";
    print FO "data=\n";
    &hex_dump ($el->{data}, *FO);
    print FO $delim, "\n\n";
}

# ----------------------------------------------------------------------------
sub dump_data_record
{
  my $b= shift;
  my $ok= shift;
  my $o= shift;

  print "dump_data_record:\n";
  print join (':', %$o), "\n";
  # print "note: $nd\n" if ($nd);

  unless ($ok && 0)
  {
    &hex_dump ($b);
  }
}

# ----------------------------------------------------------------------------
sub hex_dump
{
  my $data= shift;
  local *FX= shift || *STDOUT;

  my $off= 0;
  my ($i, $c, $v);

  while ($data)
  {
    my $char= '';
    my $hex= '';
    my $offx= sprintf ('%08X', $off);
    $off += 0x10;

    for ($i= 0; $i < 16; $i++)
    {
      $c= substr ($data, 0, 1);

      if ($c ne '')
      {
        $data= substr ($data, 1);
        $v= unpack ('C', $c);
        $c= '.' if ($v < 0x20 || $v >= 0x7F);

        $char .= $c;
        $hex .= sprintf (' %02X', $v);
      }
      else
      {
        $char .= ' ';
        $hex  .= '   ';
      }
    }

    print FX "$offx $hex $char\n";
  }
}

# ----------------------------------------------------------------------------
sub decode_password
{
  my ($b, $siz)= @_;

  my $pass= &decode ($b, $siz, \@PRE_CODE, 1);

  print "database is encrypted\npassword record, encrypted\n";
  &hex_dump ($b);
  # print "password record, decryption attempted (1)\n";
  # &hex_dump ($pass);

  my ($i, $c, $pad);
  for ($i= 15; $i > 0; $i--)
  {
    $c= unpack ('C', substr ($pass, $i, 1));
    if ($c != $PRE_PADDING [$i])
    {
      $i++;
      last;
    }
  }
  $pass= substr ($pass, 0, $i);
  print "password record, decryption attempted (2)\n";
  &hex_dump ($pass);

# NOTE: [1998-07-25 10:50:16]
# This algorithms is not quite correct yet.  The current
# padding data would make it impossible to have certain characters
# at a certain position in the passord.  E.G. this algorithm will
# strip off the last digit of the password if the password was
# 8 characters long and the original password ended with the
# character '7'.  More work needs to be done here.

  $pass;
}

# ----------------------------------------------------------------------------
sub decode
{
  my ($b, $siz, $code_ref, $is_pass)= @_;
  my $CODE_SIZE= $#$code_ref;
  my @CODE= @$code_ref;
  # my @CODE= @PRE_CODE;
  # my $CODE_SIZE= $#CODE;

  my ($bb, $ii, $jj, $cc, $c0, $kk);

  for ($ii= 0; $ii < $siz; $ii++)
  {
    $cc= $c0= unpack ('C', substr ($b, $ii, 1));

    $kk= $CODE [$jj];
    $cc= $cc ^ $kk;
    $cc= $cc ^ $jj unless ($is_pass);
    $bb .= pack ('C', $cc);

    if ($is_pass && 0)
    {
      printf "ii=$ii kk=0x%02X jj=$jj c: 0x%02X -> 0x%02X\n",
              $kk, $c0, $cc;
    }

    $jj= 0 if ($jj++ >= $CODE_SIZE);
  }

  $bb;
}

# ----------------------------------------------------------------------------
sub recover_password
{
  my $self= shift;
  my $note_nr= shift;
  my $ptx_fnm= shift;
  my $key_fnm= shift;

  # fetch encrypted note
  my $T= $self->{Types} || die;
  my $D= $T->[11];  # array of data records
  my $N= $T->[9];   # array of note records
  my $enc_txt= $N->[$note_nr]->{data};
  # print "encrypted text:\n"; &hex_dump ($enc_txt);

  # fetch plain text
  my $ptx_txt;
  open (FI, $ptx_fnm) || die;
  while (<FI>) { $ptx_txt .= $_; }
  close (FI);
  # print "plain text:\n"; &hex_dump ($ptx_txt);

  # recover the key
  my ($pp, $cc, $ee, $ii, $key);
  my $ll_enc= length ($enc_txt);
  my $ll_ptx= length ($ptx_txt);
  print "text size enc=$ll_enc plain=$ll_ptx\n";

  for ($ii= 0; $ii < $ll_ptx; $ii++)
  {
    $pp= unpack ('C', substr ($ptx_txt, $ii, 1));
    $ee= unpack ('C', substr ($enc_txt, $ii, 1));
    $cc= $pp ^ $ee ^ $ii;
    $key .= pack ('C', $cc);
  }

  # print "the key is\n"; &hex_dump ($key);

  print "dumping key to $key_fnm\n";
  open (FO, ">$key_fnm") || die;
  binmode (FI); # MS-DOS systems need this, T2D: how about Mac?
  print FO $key;
  close (FO);
}


# Autoload methods go after =cut, and are processed by the autosplit program.

1;
__END__
# POD Section

=head1 NAME

HP200LX::DB - Perl module to access HP-200 LX database files

=head1 SYNOPSIS

  use HP200LX::DB;

  interface functions:
    $db= HP200LX::DB::openDB ($fnm)     read database and return an DB object
    $db= HP200LX::DB::new ($fnm)        create database and return an DB object
    $db->saveDB ($fnm)                  save DB object as a (new) file

  array tie implementation to access database data records:
    tie (@dbd, HP200LX::DB, $db);       access database data in array form
    TIEARRAY                            stub to get an tie for the database
    FETCH                               retrieve a record
    STORE                               store a record
    $db->get_last_index ()              return highest index
    T2D: $db->DELETE ($num)             delete given data record
    T2D: $db->INSERT ($num)             insert a new object at index

  internal methods:
    $db->show_db_def (*FH)              show database definition
    $db->show_card_def (*FH)            show card layout definition
    $db->get_field_def ($num)           retrieve field definition
    show_field_def                      show a field definition
    fetch_data                          used by FETCH to get db record
    store_data                          used by STORE to save db record
    get_recheader                       read gdb internal record structure
    put_recheader                       store gdb internal record structure
    fmt_time_stamp                      create a readable date and time string
    get_fielddef                        decode a field definition record
    get_carddef                         decode a card definiton record

  Diagnostics and Debugging methods:
    $db->dump_db (*FH, $type)           dump a complete data base
    $db->dump_data                      dump all data records
    $db->recover_password               attempt to reconstruct DB password

  Diagnostics and Debugging functions:
    print_recheader (*FH, $txt, $rec)   print details about a record
    dump_def                            dump database definition
    dump_data_record                    print and dump data record
    hex_dump                            perform a hex dump of some data
    decode_password                     attempt to decote the DB password
    decode                              attempt to decode a DB recrod

=head1 DESCRIPTION

  DB.pm implements the perl package HP200LX::DB which is intended
  to provide a perl 5 interface for files in the generic database
  format of the HP 200 LX palmtop computer.  The perl modules are
  intended to be used on a work station such as a PC or a Unix
  machine to read and write data records from and to a database
  file.  These modules are not intended to be run directly on the
  palmtop!

  Please see the README file for a few more details or consult
  the examples which can be found at the web site mentioned below.

=head1 Copyright

  Copyright (c) 1998 Gerhard Gonter.  All rights reserved.
  This is free software; you can redistribute it and/or modify
  it under the same terms as Perl itself.

=head1 AUTHOR

  Gerhard Gonter, g.gonter@ieee.org or gonter@wu-wien.ac.at

=head1 SEE ALSO

  http://falbala.wu-wien.ac.at:8684/pub/english.cgi/0/24065
  perl(1).

=cut
