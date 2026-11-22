output "backup_bucket" {
  value = aws_s3_bucket.backup.id
}

output "backup_bucket_arn" {
  value = aws_s3_bucket.backup.arn
}

output "backup_dr_bucket" {
  value = aws_s3_bucket.backup_dr.id
}

output "log_bucket" {
  value = aws_s3_bucket.logs.id
}
