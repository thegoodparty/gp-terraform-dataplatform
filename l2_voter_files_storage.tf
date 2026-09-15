# =============================================================================
# L2 voter-file staging retention
#
# The load_l2_voter_files DAG stages every L2 delivery under
# l2_data/from_sftp_server/VMFiles/<env>/ and never deletes anything (its role has no
# s3:DeleteObject). L2 refreshes every state roughly monthly, so prod accrues ~1.1 TB a
# month of superseded snapshots. Research and engineering leadership ruled (2026-09-15):
# keep the history, but in cold storage, not Standard.
#
# The bucket itself is Databricks-created and not managed here; only its lifecycle
# configuration is. This resource is authoritative for that configuration, and the
# bucket had none before.
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "l2_voter_files" {
  bucket = local.l2_voter_files_bucket

  # Prod snapshots go cold after 45 days. By then L2 has republished the state, so the
  # DAG's planner (S3 LastModified vs SFTP mtime, storage class ignored) still sees the
  # file as staged and never re-copies it, and the table it built is already newer than
  # the file, so it never tries to read it back. The one way to hit an archived object is
  # to drop a table by hand and force a rebuild from a file older than 45 days; restore it
  # from Deep Archive first, or let the next L2 delivery supersede it.
  rule {
    id     = "l2-voter-files-prod-archive"
    status = "Enabled"
    filter {
      prefix = "${local.l2_voter_files_prefix}/from_sftp_server/VMFiles/prod/"
    }
    transition {
      days          = 45
      storage_class = "DEEP_ARCHIVE"
    }
  }

  # Dev snapshots have no history value; drop them after two months.
  rule {
    id     = "l2-voter-files-dev-expire"
    status = "Enabled"
    filter {
      prefix = "${local.l2_voter_files_prefix}/from_sftp_server/VMFiles/dev_dball/"
    }
    expiration {
      days = 60
    }
  }

  # A sync killed mid-upload leaves multipart parts that are billed but invisible.
  rule {
    id     = "l2-voter-files-abort-multipart"
    status = "Enabled"
    filter {
      prefix = "${local.l2_voter_files_prefix}/"
    }
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
}
