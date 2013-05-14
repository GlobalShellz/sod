package Sod::Schema::Result::Ip;

# Created by DBIx::Class::Schema::Loader
# DO NOT MODIFY THE FIRST PART OF THIS FILE

use strict;
use warnings;

use base 'DBIx::Class::Core';

__PACKAGE__->load_components("InflateColumn::DateTime");

=head1 NAME

Sod::Schema::Result::Ip

=cut

__PACKAGE__->table("ip");

=head1 ACCESSORS

=head2 id

  data_type: 'integer'
  is_auto_increment: 1
  is_nullable: 0

=head2 a

  data_type: 'integer'
  is_nullable: 1

=head2 b

  data_type: 'integer'
  is_nullable: 1

=head2 c

  data_type: 'integer'
  is_nullable: 1

=head2 d

  data_type: 'integer'
  is_nullable: 1

=head2 open

  data_type: 'integer'
  is_nullable: 1

=head2 date

  data_type: 'datetime'
  default_value: current_timestamp
  is_nullable: 1

=cut

__PACKAGE__->add_columns(
  "id",
  { data_type => "integer", is_auto_increment => 1, is_nullable => 0 },
  "a",
  { data_type => "integer", is_nullable => 1 },
  "b",
  { data_type => "integer", is_nullable => 1 },
  "c",
  { data_type => "integer", is_nullable => 1 },
  "d",
  { data_type => "integer", is_nullable => 1 },
  "open",
  { data_type => "integer", is_nullable => 1 },
  "date",
  {
    data_type     => "datetime",
    default_value => \"current_timestamp",
    is_nullable   => 1,
  },
);
__PACKAGE__->set_primary_key("id");


# Created by DBIx::Class::Schema::Loader v0.07010 @ 2013-05-14 19:00:54
# DO NOT MODIFY THIS OR ANYTHING ABOVE! md5sum:u1+Ys9tCBgAKLoDahdYMaA


# You can replace this text with custom code or comments, and it will be preserved on regeneration
1;
