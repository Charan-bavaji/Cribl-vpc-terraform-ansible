# Why routes on BOTH sides are required: the peering connection itself
# only creates the possibility of a path between the two VPCs. Without an
# explicit route in each VPC's route table pointing the other VPC's CIDR
# at this peering connection, nothing actually knows to use it - this is
# the step that's most commonly forgotten when setting up peering.
resource "aws_vpc_peering_connection" "this" {
  vpc_id      = var.requester_vpc_id
  peer_vpc_id = var.accepter_vpc_id
  auto_accept = true # safe here since both VPCs are in the same account

  tags = {
    Name = "vpc1-vpc2-peering"
  }
}

resource "aws_route" "requester_to_accepter" {
  count                     = length(var.requester_route_table_ids)
  route_table_id            = var.requester_route_table_ids[count.index]
  destination_cidr_block    = var.accepter_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}

resource "aws_route" "accepter_to_requester" {
  count                     = length(var.accepter_route_table_ids)
  route_table_id            = var.accepter_route_table_ids[count.index]
  destination_cidr_block    = var.requester_cidr
  vpc_peering_connection_id = aws_vpc_peering_connection.this.id
}
