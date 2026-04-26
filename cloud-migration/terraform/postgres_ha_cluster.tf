resource "aws_db_instance" "primary" {
  engine = "postgres"
  instance_class = "db.t3.medium"
  allocated_storage = 50
  multi_az = true
}

resource "aws_db_instance" "replica" {
  replicate_source_db = aws_db_instance.primary.id
  instance_class = "db.t3.medium"
}
