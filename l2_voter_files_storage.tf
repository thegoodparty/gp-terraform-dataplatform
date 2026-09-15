# =============================================================================
# L2 voter-file staging retention
#
# The load_l2_voter_files DAG stages every L2 delivery under
# l2_data/from_sftp_server/VMFiles/prod/ and never deletes anything (its role has no
# s3:DeleteObject). L2 refreshes every state roughly monthly, so prod accrues ~1.1 TB a
# month of superseded snapshots. Research and engineering leadership ruled (2026-09-15):
# keep the history, but in cold storage, not Standard.
#
# The bucket itself is Databricks-created and not managed here; only its lifecycle
# configuration is. This resource is authoritative for the bucket's whole lifecycle
# configuration (it had none before), so any future rule, including one for a dev
# staging prefix, has to be added here rather than in the console.
# =============================================================================

resource "aws_s3_bucket_lifecycle_configuration" "l2_voter_files" {
  bucket = local.l2_voter_files_bucket

  # A staged file is read exactly once, by the rebuild in the same run that copied it.
  # Afterwards it only serves as the planner's "already staged" marker (S3 LastModified vs
  # SFTP mtime; storage class is ignored), so it can go cold almost immediately. Seven
  # days keeps it readable through the DAG's self-heal window: a rebuild that fails is
  # re-planned by the following runs and needs the file back. The one way to hit an
  # archived object after that is to drop a table by hand and force a rebuild from an old
  # file; restore it from Deep Archive first, or let the next L2 delivery supersede it.
  rule {
    id     = "l2-voter-files-prod-archive"
    status = "Enabled"
    filter {
      prefix = "${local.l2_voter_files_prefix}/from_sftp_server/VMFiles/prod/"
    }
    transition {
      days          = 7
      storage_class = "DEEP_ARCHIVE"
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
