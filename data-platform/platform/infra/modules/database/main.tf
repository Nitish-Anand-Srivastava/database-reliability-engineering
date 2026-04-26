resource "aws_db_instance" "postgres" {
  engine = "postgres"
  instance_class = "db.t3.medium"
  multi_az = true
}
