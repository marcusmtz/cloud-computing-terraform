resource "aws_ebs_volume" "windows_ad_backup" {
  count = var.enable_windows_server && var.enable_ad_system_state_backup ? 1 : 0

  availability_zone = aws_instance.windows_server[0].availability_zone
  size              = var.windows_ad_backup_volume_size
  type              = "gp3"
  encrypted         = true

  tags = {
    Name    = "${var.project_name}-${var.environment}-ad-system-state-backup"
    Purpose = "One-time encrypted Windows Server Backup target for AD DS system state"
  }
}

resource "aws_volume_attachment" "windows_ad_backup" {
  count = var.enable_windows_server && var.enable_ad_system_state_backup ? 1 : 0

  device_name = "/dev/sdf"
  volume_id   = aws_ebs_volume.windows_ad_backup[0].id
  instance_id = aws_instance.windows_server[0].id
}

# Prepare only a blank disk of the configured size. Existing filesystems or
# unexpected disks are never formatted or altered by this association.
resource "aws_ssm_association" "windows_ad_backup_disk_prepare" {
  count = var.enable_windows_server && var.enable_ad_system_state_backup ? 1 : 0

  name             = "AWS-RunPowerShellScript"
  association_name = "${var.project_name}-${var.environment}-ad-backup-disk-prepare"
  parameters = {
    commands = <<-POWERSHELL
      $ErrorActionPreference = 'Stop'
      $label = 'NORCOMADBACKUP'
      $expectedBytes = ${var.windows_ad_backup_volume_size} * 1GB
      $labeledVolumes = @(Get-Volume -FileSystemLabel $label -ErrorAction SilentlyContinue)
      if ($labeledVolumes.Count -gt 1) { throw "More than one volume is labeled $label; no disk was changed." }
      $volume = $labeledVolumes | Select-Object -First 1

      if (-not $volume) {
        $minBytes = [long]($expectedBytes * 0.95)
        $maxBytes = [long]($expectedBytes * 1.05)
        $rawDisks = @(Get-Disk | Where-Object {
          $_.PartitionStyle -eq 'RAW' -and $_.Size -ge $minBytes -and $_.Size -le $maxBytes
        })
        if ($rawDisks.Count -ne 1) {
          throw "Expected one blank ${var.windows_ad_backup_volume_size}-GiB backup disk; found $($rawDisks.Count). No disk was formatted."
        }

        $disk = $rawDisks[0]
        if ($disk.IsOffline) { Set-Disk -Number $disk.Number -IsOffline $false }
        if ($disk.IsReadOnly) { Set-Disk -Number $disk.Number -IsReadOnly $false }
        Initialize-Disk -Number $disk.Number -PartitionStyle GPT | Out-Null
        $partition = New-Partition -DiskNumber $disk.Number -UseMaximumSize -DriveLetter R
        Format-Volume -Partition $partition -FileSystem NTFS -NewFileSystemLabel $label -Confirm:$false | Out-Null
        $volume = Get-Volume -FileSystemLabel $label
      }

      if ($volume.FileSystem -ne 'NTFS') { throw "The labeled AD backup volume is not NTFS; found $($volume.FileSystem)." }
      if ($volume.DriveLetter -ne 'R') {
        if (Get-Volume -DriveLetter R -ErrorAction SilentlyContinue) { throw 'Drive letter R is already in use; no change made.' }
        $partition = Get-Partition -Volume $volume
        Set-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -NewDriveLetter R
      }
      $partition = Get-Partition -DriveLetter R -ErrorAction Stop
      $disk = Get-Disk -Number $partition.DiskNumber -ErrorAction Stop
      $minBytes = [long]($expectedBytes * 0.95)
      $maxBytes = [long]($expectedBytes * 1.05)
      if ($disk.Size -lt $minBytes -or $disk.Size -gt $maxBytes) {
        throw "The labeled backup disk size ($($disk.Size) bytes) does not match the configured ${var.windows_ad_backup_volume_size} GiB. No partition was changed."
      }
      if ($disk.IsOffline) { Set-Disk -Number $disk.Number -IsOffline $false }
      if ($disk.IsReadOnly) { Set-Disk -Number $disk.Number -IsReadOnly $false }
      $supported = Get-PartitionSupportedSize -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber
      if ($supported.SizeMax -gt $partition.Size) {
        Resize-Partition -DiskNumber $partition.DiskNumber -PartitionNumber $partition.PartitionNumber -Size $supported.SizeMax
      }
      $volume = Get-Volume -DriveLetter R -ErrorAction Stop
      if ($volume.Size -lt $minBytes) { throw "The R: filesystem could not be extended to the configured ${var.windows_ad_backup_volume_size} GiB. No backup was started." }
      Write-Output "NORCOM_AD_BACKUP_TARGET_READY=R: LABEL=$label SIZE_BYTES=$($volume.Size)"
    POWERSHELL
  }

  targets {
    key    = "InstanceIds"
    values = [aws_instance.windows_server[0].id]
  }

  wait_for_success_timeout_seconds = 1800
  depends_on                       = [aws_volume_attachment.windows_ad_backup]
}
