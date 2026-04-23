param(
    [string]$ProcessedCsvPath,
    [string]$AnalysisCsvPath
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

try {
    if (-not (Test-Path $ProcessedCsvPath)) {
        Write-Output "ANALYSIS_FAILED|processed_invoices.csv not found"
        exit
    }

    $data = Import-Csv -Path $ProcessedCsvPath

    if (-not $data -or $data.Count -eq 0) {
        Write-Output "ANALYSIS_FAILED|No processed records found"
        exit
    }

    Ensure-FileWithHeader -Path $AnalysisCsvPath -Header "RunDate,FileName,RowNumber,InvoiceNumber,Supplier,Amount,Date,AmountCategory,RiskFlag,AnalysisNote"

    foreach ($row in $data) {
        $runDate = $row.RunDate
        $fileName = $row.FileName
        $rowNumber = $row.RowNumber
        $invoiceNumber = $row.InvoiceNumber
        $supplier = $row.Supplier
        $amount = $row.Amount
        $date = $row.Date

        $normalizedAmount = $amount -replace ',', '.'
        $parsedAmount = 0

        $amountIsNumber = [decimal]::TryParse(
            $normalizedAmount,
            [System.Globalization.NumberStyles]::Any,
            [System.Globalization.CultureInfo]::InvariantCulture,
            [ref]$parsedAmount
        )

        if (-not $amountIsNumber) {
            continue
        }

        if ($parsedAmount -lt 1000) {
            $amountCategory = "LOW"
            $riskFlag = "NO"
            $analysisNote = "Standard invoice"
        }
        elseif ($parsedAmount -le 3000) {
            $amountCategory = "MEDIUM"
            $riskFlag = "NO"
            $analysisNote = "Standard invoice"
        }
        else {
            $amountCategory = "HIGH"
            $riskFlag = "YES"
            $analysisNote = "High-value invoice"
        }

        $escapedInvoiceNumber = Escape-CsvValue -Value $invoiceNumber
        $escapedSupplier = Escape-CsvValue -Value $supplier
        $escapedAmount = Escape-CsvValue -Value $amount
        $escapedDate = Escape-CsvValue -Value $date
        $escapedCategory = Escape-CsvValue -Value $amountCategory
        $escapedRiskFlag = Escape-CsvValue -Value $riskFlag
        $escapedNote = Escape-CsvValue -Value $analysisNote

        Add-Line -Path $AnalysisCsvPath -Line "$runDate,$fileName,$rowNumber,$escapedInvoiceNumber,$escapedSupplier,$escapedAmount,$escapedDate,$escapedCategory,$escapedRiskFlag,$escapedNote"
    }

    Write-Output "ANALYSIS_OK"
}
catch {
    Write-Output "ANALYSIS_FAILED|$($_.Exception.Message)"
}