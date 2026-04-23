param(
    [string]$FilePath,
    [string]$ProcessedCsvPath,
    [string]$ErrorCsvPath,
    [string]$RunSummaryCsvPath
)

function Ensure-FileWithHeader {
    param(
        [string]$Path,
        [string]$Header
    )

    if (-not (Test-Path $Path)) {
        Set-Content -Path $Path -Value $Header -Encoding UTF8
    }
}

function Add-Line {
    param(
        [string]$Path,
        [string]$Line
    )

    Add-Content -Path $Path -Value $Line -Encoding UTF8
}

function Escape-CsvValue {
    param(
        [string]$Value
    )

    if ($null -eq $Value) {
        return '""'
    }

    $escaped = $Value.Replace('"', '""')
    return '"' + $escaped + '"'
}

$fileName = Split-Path $FilePath -Leaf
$runDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"

try {
    if (-not (Test-Path $FilePath)) {
        Write-Output "RESULT_INVALID|File not found"
        exit
    }

    Ensure-FileWithHeader -Path $ProcessedCsvPath -Header "RunDate,FileName,RowNumber,InvoiceNumber,Supplier,Amount,Date,Status"
    Ensure-FileWithHeader -Path $ErrorCsvPath -Header "RunDate,FileName,RowNumber,InvoiceNumber,ErrorReason,Status"
    Ensure-FileWithHeader -Path $RunSummaryCsvPath -Header "RunDate,FileName,TotalRows,ValidRows,InvalidRows,FileStatus"

    $data = Import-Csv -Path $FilePath

    if (-not $data -or $data.Count -eq 0) {
        Add-Line -Path $ErrorCsvPath -Line "$runDate,$fileName,0,,Empty CSV file,INVALID"
        Add-Line -Path $RunSummaryCsvPath -Line "$runDate,$fileName,0,0,1,INVALID"
        Write-Output "RESULT_INVALID|Empty CSV file"
        exit
    }

    $requiredColumns = @("InvoiceNumber", "Supplier", "Amount", "Date")
    $columns = $data[0].PSObject.Properties.Name

    foreach ($requiredColumn in $requiredColumns) {
        if ($columns -notcontains $requiredColumn) {
            Add-Line -Path $ErrorCsvPath -Line "$runDate,$fileName,0,,Missing required column: $requiredColumn,INVALID"
            Add-Line -Path $RunSummaryCsvPath -Line "$runDate,$fileName,0,0,1,INVALID"
            Write-Output "RESULT_INVALID|Missing required column: $requiredColumn"
            exit
        }
    }

    $seenInvoiceNumbers = @{}
    $rowNumber = 1
    $validRows = 0
    $invalidRows = 0

    foreach ($row in $data) {
        $rowNumber++
        $invoiceNumber = $row.InvoiceNumber
        $supplier = $row.Supplier
        $amount = $row.Amount
        $date = $row.Date

        $errorReason = $null

        if ([string]::IsNullOrWhiteSpace($invoiceNumber)) {
            $errorReason = "Missing invoice number"
        }
        elseif ([string]::IsNullOrWhiteSpace($supplier)) {
            $errorReason = "Missing supplier"
        }
        else {
            $normalizedAmount = $amount -replace ',', '.'
            $parsedAmount = 0
            $amountIsNumber = [decimal]::TryParse(
                $normalizedAmount,
                [System.Globalization.NumberStyles]::Any,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$parsedAmount
            )

            if (-not $amountIsNumber) {
                $errorReason = "Amount is not numeric"
            }
            elseif ($parsedAmount -le 0) {
                $errorReason = "Amount must be greater than zero"
            }
            elseif ([string]::IsNullOrWhiteSpace($date)) {
                $errorReason = "Missing date"
            }
            else {
                try {
					$parsedDate = Get-Date $date -ErrorAction Stop
				}
				catch {
					$parsedDate = $null
				}

				if ($null -eq $parsedDate) {
					$errorReason = "Invalid date format"
				}
				elseif ($seenInvoiceNumbers.ContainsKey($invoiceNumber)) {
					$errorReason = "Duplicate invoice number"
				}
            }
        }

        if ($null -ne $errorReason) {
            $invalidRows++
            $escapedInvoiceNumber = Escape-CsvValue -Value $invoiceNumber
            $escapedReason = Escape-CsvValue -Value $errorReason
            Add-Line -Path $ErrorCsvPath -Line "$runDate,$fileName,$rowNumber,$escapedInvoiceNumber,$escapedReason,INVALID"
        }
        else {
            $seenInvoiceNumbers[$invoiceNumber] = $true
            $validRows++

            $escapedInvoiceNumber = Escape-CsvValue -Value $invoiceNumber
            $escapedSupplier = Escape-CsvValue -Value $supplier
            $escapedAmount = Escape-CsvValue -Value $amount
            $escapedDate = Escape-CsvValue -Value $date

            Add-Line -Path $ProcessedCsvPath -Line "$runDate,$fileName,$rowNumber,$escapedInvoiceNumber,$escapedSupplier,$escapedAmount,$escapedDate,VALID"
        }
    }

    $fileStatus = if ($invalidRows -gt 0) { "PARTIAL_OR_INVALID" } else { "VALID" }
    Add-Line -Path $RunSummaryCsvPath -Line "$runDate,$fileName,$($data.Count),$validRows,$invalidRows,$fileStatus"

    if ($validRows -gt 0) {
        Write-Output "RESULT_VALID|ValidRows=$validRows|InvalidRows=$invalidRows"
    }
    else {
        Write-Output "RESULT_INVALID|No valid rows"
    }
}
catch {
    Ensure-FileWithHeader -Path $ErrorCsvPath -Header "RunDate,FileName,RowNumber,InvoiceNumber,ErrorReason,Status"
    Ensure-FileWithHeader -Path $RunSummaryCsvPath -Header "RunDate,FileName,TotalRows,ValidRows,InvalidRows,FileStatus"

    $escapedException = Escape-CsvValue -Value $_.Exception.Message
    Add-Line -Path $ErrorCsvPath -Line "$runDate,$fileName,0,,$escapedException,INVALID"
    Add-Line -Path $RunSummaryCsvPath -Line "$runDate,$fileName,0,0,1,INVALID"
    Write-Output "RESULT_INVALID|$($_.Exception.Message)"
}