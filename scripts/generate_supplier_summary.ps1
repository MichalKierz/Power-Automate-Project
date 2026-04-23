param(
    [string]$ProcessedCsvPath,
    [string]$SupplierSummaryCsvPath
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
        Write-Output "SUMMARY_FAILED|processed_invoices.csv not found"
        exit
    }

    $data = Import-Csv -Path $ProcessedCsvPath

    if (-not $data -or $data.Count -eq 0) {
        Write-Output "SUMMARY_FAILED|No processed records found"
        exit
    }

    Ensure-FileWithHeader -Path $SupplierSummaryCsvPath -Header "Supplier,InvoiceCount,TotalAmount,AverageAmount,MaxAmount,HighRiskInvoiceCount"

    $grouped = $data | Group-Object Supplier

    foreach ($group in $grouped) {
        $supplier = $group.Name
        $rows = $group.Group

        $invoiceCount = $rows.Count
        $totalAmount = 0
        $maxAmount = 0
        $highRiskInvoiceCount = 0

        foreach ($row in $rows) {
            $amount = $row.Amount -replace ',', '.'
            $parsedAmount = 0

            $amountIsNumber = [decimal]::TryParse(
                $amount,
                [System.Globalization.NumberStyles]::Any,
                [System.Globalization.CultureInfo]::InvariantCulture,
                [ref]$parsedAmount
            )

            if (-not $amountIsNumber) {
                continue
            }

            $totalAmount += $parsedAmount

            if ($parsedAmount -gt $maxAmount) {
                $maxAmount = $parsedAmount
            }

            if ($parsedAmount -gt 3000) {
                $highRiskInvoiceCount++
            }
        }

        if ($invoiceCount -gt 0) {
            $averageAmount = [math]::Round(($totalAmount / $invoiceCount), 2)
        }
        else {
            $averageAmount = 0
        }

        $escapedSupplier = Escape-CsvValue -Value $supplier
        $escapedTotal = Escape-CsvValue -Value ([string]([math]::Round($totalAmount, 2)))
        $escapedAverage = Escape-CsvValue -Value ([string]$averageAmount)
        $escapedMax = Escape-CsvValue -Value ([string]$maxAmount)

        Add-Line -Path $SupplierSummaryCsvPath -Line "$escapedSupplier,$invoiceCount,$escapedTotal,$escapedAverage,$escapedMax,$highRiskInvoiceCount"
    }

    Write-Output "SUMMARY_OK"
}
catch {
    Write-Output "SUMMARY_FAILED|$($_.Exception.Message)"
}