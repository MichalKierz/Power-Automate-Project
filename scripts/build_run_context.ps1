$now = Get-Date
$runId = $now.ToString("yyyyMMdd_HHmmss")
$runDate = $now.ToString("yyyy-MM-dd HH:mm:ss")

Write-Output "$runId|$runDate"