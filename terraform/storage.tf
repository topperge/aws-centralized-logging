#==============================================================================
# S3 buckets: Firehose backup bucket and its server access logs bucket
#==============================================================================
resource "aws_s3_bucket" "access_logs" {
  bucket_prefix = "${lower(var.name_prefix)}-access-logs-"
}

resource "aws_s3_bucket" "firehose" {
  bucket_prefix = "${lower(var.name_prefix)}-firehose-"
}

resource "aws_s3_bucket_server_side_encryption_configuration" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "firehose" {
  bucket = aws_s3_bucket.firehose.id
  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "access_logs" {
  bucket                  = aws_s3_bucket.access_logs.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_public_access_block" "firehose" {
  bucket                  = aws_s3_bucket.firehose.id
  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_logging" "firehose" {
  bucket        = aws_s3_bucket.firehose.id
  target_bucket = aws_s3_bucket.access_logs.id
  target_prefix = "cl-access-logs"
}

data "aws_iam_policy_document" "access_logs" {
  statement {
    sid     = "EnforceSSL"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.access_logs.arn, "${aws_s3_bucket.access_logs.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid     = "S3ServerAccessLogsPolicy"
    actions = ["s3:PutObject"]
    principals {
      type        = "Service"
      identifiers = ["logging.s3.amazonaws.com"]
    }
    resources = ["${aws_s3_bucket.access_logs.arn}/cl-access-logs*"]
    condition {
      test     = "ArnLike"
      variable = "aws:SourceArn"
      values   = [aws_s3_bucket.firehose.arn]
    }
    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [local.account_id]
    }
  }
}

resource "aws_s3_bucket_policy" "access_logs" {
  bucket = aws_s3_bucket.access_logs.id
  policy = data.aws_iam_policy_document.access_logs.json

  depends_on = [aws_s3_bucket_public_access_block.access_logs]
}

data "aws_iam_policy_document" "firehose_bucket" {
  statement {
    sid     = "EnforceSSL"
    effect  = "Deny"
    actions = ["s3:*"]
    principals {
      type        = "AWS"
      identifiers = ["*"]
    }
    resources = [aws_s3_bucket.firehose.arn, "${aws_s3_bucket.firehose.arn}/*"]
    condition {
      test     = "Bool"
      variable = "aws:SecureTransport"
      values   = ["false"]
    }
  }
  statement {
    sid     = "FirehoseAccess"
    actions = ["s3:Put*", "s3:Get*"]
    principals {
      type        = "AWS"
      identifiers = [aws_iam_role.firehose.arn]
    }
    resources = [aws_s3_bucket.firehose.arn, "${aws_s3_bucket.firehose.arn}/*"]
  }
}

resource "aws_s3_bucket_policy" "firehose" {
  bucket = aws_s3_bucket.firehose.id
  policy = data.aws_iam_policy_document.firehose_bucket.json

  depends_on = [aws_s3_bucket_public_access_block.firehose]
}
