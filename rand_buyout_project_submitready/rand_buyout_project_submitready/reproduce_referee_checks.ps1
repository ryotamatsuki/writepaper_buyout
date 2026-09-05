$ErrorActionPreference = 'Stop'
Set-StrictMode -Version Latest

function Show-Section {
    param([string]$Title)
    Write-Output ""
    Write-Output ("=" * 88)
    Write-Output $Title
    Write-Output ("=" * 88)
}

function Write-Table {
    param($Rows)
    Write-Output (($Rows | Format-Table -AutoSize | Out-String -Width 240).TrimEnd())
}

function Write-List {
    param($Item)
    Write-Output (($Item | Format-List | Out-String -Width 240).TrimEnd())
}

function Get-ProjectStats {
    param(
        [string]$Name,
        [double]$a,
        [double]$sigma,
        [double]$m,
        [double]$etaD,
        [double]$etaA,
        [double]$xiD,
        [double]$xiA
    )

    $qI_D = (2.0 - $a * $sigma) / (4.0 - $sigma * $sigma)
    $qE_D = (2.0 * $a - $sigma) / (4.0 - $sigma * $sigma)
    $piI_D = $qI_D * $qI_D
    $piE_D = $qE_D * $qE_D
    $C_D = 0.5 * ($qI_D * $qI_D + $qE_D * $qE_D + 2.0 * $sigma * $qI_D * $qE_D)

    $qI_M = (1.0 - $a * $sigma) / (2.0 * (1.0 - $sigma * $sigma))
    $qE_M = ($a - $sigma) / (2.0 * (1.0 - $sigma * $sigma))
    $PiOp_M = ($a * $a - 2.0 * $a * $sigma + 1.0) / (4.0 * (1.0 - $sigma * $sigma))
    $Pi_M = $PiOp_M + $m
    $C_M = 0.5 * ($qI_M * $qI_M + $qE_M * $qE_M + 2.0 * $sigma * $qI_M * $qE_M)

    $Delta = $Pi_M - $piI_D - $piE_D
    $V_D = $C_D + $piI_D + $piE_D
    $V_A = $C_M + $Pi_M
    $Omega = $V_A - $V_D

    [pscustomobject]@{
        Name   = $Name
        a      = $a
        sigma  = $sigma
        m      = $m
        etaD   = $etaD
        etaA   = $etaA
        xiD    = $xiD
        xiA    = $xiA
        qI_D   = $qI_D
        qE_D   = $qE_D
        piI_D  = $piI_D
        piE_D  = $piE_D
        C_D    = $C_D
        qI_M   = $qI_M
        qE_M   = $qE_M
        PiOp_M = $PiOp_M
        Pi_M   = $Pi_M
        C_M    = $C_M
        Delta  = $Delta
        V_D    = $V_D
        V_A    = $V_A
        Omega  = $Omega
    }
}

function Get-Thresholds {
    param(
        $ProjectI,
        $ProjectB,
        [double]$beta,
        [double]$k
    )

    [pscustomobject]@{
        qbarI = $k / $ProjectI.Delta
        qbarB = $k / $ProjectB.Delta
        qhat  = ($ProjectI.piE_D - $ProjectB.piE_D) / ($beta * ($ProjectB.Delta - $ProjectI.Delta))
    }
}

function Get-ContinuationValue {
    param(
        $Project,
        [double]$q,
        [double]$beta,
        [double]$k,
        [double]$rho = 0.0
    )

    $netGain = $q * $Project.Delta - $k
    $afterClawback = (1.0 - $rho) * $beta * [math]::Max($netGain, 0.0)
    $Project.piE_D + $afterClawback
}

function Get-PrimitiveBenchmarkObjects {
    param(
        $Project,
        [double]$q,
        [double]$beta,
        [double]$k,
        [double]$tau
    )

    $attempt = [int](($q * $Project.Delta - $k) -ge 0.0)
    $R = Get-ContinuationValue -Project $Project -q $q -beta $beta -k $k
    $BPM = $Project.V_D + $attempt * ($q * $Project.Omega - $k)
    $unconstrained = ($R * $BPM - (($tau + 2.0) / 2.0) * $R * $R) / (2.0 * $tau + 1.0)
    $sPM = [math]::Max(0.0, $unconstrained)

    [pscustomobject]@{
        Attempt                 = $attempt
        R                       = $R
        BPM                     = $BPM
        UnconstrainedBenchmark  = $unconstrained
        sPM                     = $sPM
    }
}

function Get-LocalNationalObjects {
    param(
        $Project,
        [double]$q,
        [double]$k,
        [double]$lambdaI_L,
        [double]$lambdaE_L,
        [double]$lambdaM_L,
        [double]$kappaL,
        [double]$kappaN,
        [double]$bonusLocalApproved = 0.0
    )

    $attempt = [int](($q * $Project.Delta - $k) -ge 0.0)

    $BLD = $Project.C_D + $lambdaI_L * $Project.piI_D + $lambdaE_L * $Project.piE_D + $Project.etaD
    $BLA = $Project.C_M + $lambdaM_L * $Project.Pi_M + $Project.etaA + $bonusLocalApproved
    $BL = $BLD + $attempt * ($q * ($BLA - $BLD) - $kappaL * $k)

    $BND = $Project.C_D + $Project.piI_D + $Project.piE_D + $Project.xiD
    $BNA = $Project.C_M + $Project.Pi_M + $Project.xiA
    $BN = $BND + $attempt * ($q * ($BNA - $BND) - $kappaN * $k)

    [pscustomobject]@{
        Attempt = $attempt
        BLD     = $BLD
        BLA     = $BLA
        BL      = $BL
        BND     = $BND
        BNA     = $BNA
        BN      = $BN
    }
}

function Get-TypeSubsidies {
    param(
        $Project,
        [double]$q,
        [double]$beta,
        [double]$k,
        [double]$tau,
        [double]$lambdaI_L,
        [double]$lambdaE_L,
        [double]$lambdaM_L,
        [double]$kappaL,
        [double]$kappaN,
        [double]$bonusLocalApproved = 0.0
    )

    $bench = Get-PrimitiveBenchmarkObjects -Project $Project -q $q -beta $beta -k $k -tau $tau
    $incidence = Get-LocalNationalObjects -Project $Project -q $q -k $k -lambdaI_L $lambdaI_L -lambdaE_L $lambdaE_L -lambdaM_L $lambdaM_L -kappaL $kappaL -kappaN $kappaN -bonusLocalApproved $bonusLocalApproved

    $sL = [math]::Max(0.0, ($bench.R * $incidence.BL - (($tau + 2.0) / 2.0) * $bench.R * $bench.R) / (2.0 * $tau + 1.0))
    $sN = [math]::Max(0.0, ($bench.R * $incidence.BN - (($tau + 2.0) / 2.0) * $bench.R * $bench.R) / (2.0 * $tau + 1.0))

    [pscustomobject]@{
        Name                    = $Project.Name
        q                       = $q
        Attempt                 = $bench.Attempt
        R                       = $bench.R
        BPM                     = $bench.BPM
        UnconstrainedBenchmark  = $bench.UnconstrainedBenchmark
        sPM                     = $bench.sPM
        BL                      = $incidence.BL
        BN                      = $incidence.BN
        D_L                     = $incidence.BL - $bench.BPM
        D_N                     = $incidence.BN - $bench.BPM
        sL                      = $sL
        sN                      = $sN
        Wedge                   = $sL - $sN
    }
}

function Get-SelectedProjectResult {
    param(
        [double]$q,
        $ProjectI,
        $ProjectB,
        $Thresholds,
        [double]$beta,
        [double]$k,
        [double]$tau,
        [double]$lambdaI_L,
        [double]$lambdaE_L,
        [double]$lambdaM_L,
        [double]$kappaL,
        [double]$kappaN,
        [switch]$UseBOnTie,
        [double]$bonusBLocalApproved = 0.0
    )

    if ($q -lt $Thresholds.qhat) {
        $chosen = $ProjectI
        $bonus = 0.0
        $choice = 'I'
    } elseif ($q -gt $Thresholds.qhat) {
        $chosen = $ProjectB
        $bonus = $bonusBLocalApproved
        $choice = 'B'
    } else {
        if ($UseBOnTie) {
            $chosen = $ProjectB
            $bonus = $bonusBLocalApproved
            $choice = 'B (tie)'
        } else {
            $chosen = $ProjectI
            $bonus = 0.0
            $choice = 'I (tie)'
        }
    }

    $result = Get-TypeSubsidies -Project $chosen -q $q -beta $beta -k $k -tau $tau -lambdaI_L $lambdaI_L -lambdaE_L $lambdaE_L -lambdaM_L $lambdaM_L -kappaL $kappaL -kappaN $kappaN -bonusLocalApproved $bonus

    [pscustomobject]@{
        q       = $q
        Choice  = $choice
        R       = $result.R
        sPM     = $result.sPM
        sL      = $result.sL
        sN      = $result.sN
        Wedge   = $result.Wedge
    }
}

function Compare-BenchmarkDerivative {
    param(
        $Project,
        [double]$q,
        [double]$beta,
        [double]$k,
        [double]$tau
    )

    $h = 1e-6
    $up = (Get-TypeSubsidies -Project $Project -q ($q + $h) -beta $beta -k $k -tau $tau -lambdaI_L 0.2 -lambdaE_L 0.7 -lambdaM_L 0.15 -kappaL 1.0 -kappaN 1.0).sPM
    $down = (Get-TypeSubsidies -Project $Project -q ($q - $h) -beta $beta -k $k -tau $tau -lambdaI_L 0.2 -lambdaE_L 0.7 -lambdaM_L 0.15 -kappaL 1.0 -kappaN 1.0).sPM
    $finiteDiff = ($up - $down) / (2.0 * $h)

    $bench = Get-PrimitiveBenchmarkObjects -Project $Project -q $q -beta $beta -k $k -tau $tau
    $formula = ($beta * $Project.Delta * ($bench.BPM - ($tau + 2.0) * $bench.R) + $bench.R * $Project.Omega) / (2.0 * $tau + 1.0)

    [pscustomobject]@{
        Project        = $Project.Name
        q              = $q
        FiniteDiff     = $finiteDiff
        Formula        = $formula
        AbsoluteGap    = [math]::Abs($finiteDiff - $formula)
    }
}

function Compare-Proposition6 {
    param(
        $Project,
        [double]$q,
        [double]$beta,
        [double]$k,
        [double]$tau,
        [double]$lambdaI_L,
        [double]$lambdaE_L,
        [double]$lambdaM_L,
        [double]$kappaL,
        [double]$kappaN
    )

    $res = Get-TypeSubsidies -Project $Project -q $q -beta $beta -k $k -tau $tau -lambdaI_L $lambdaI_L -lambdaE_L $lambdaE_L -lambdaM_L $lambdaM_L -kappaL $kappaL -kappaN $kappaN
    $rhsL_using_constrained_benchmark = $res.sPM + $res.R * $res.D_L / (2.0 * $tau + 1.0)
    $rhsN_using_constrained_benchmark = $res.sPM + $res.R * $res.D_N / (2.0 * $tau + 1.0)
    $rhsL_using_unconstrained_benchmark = $res.UnconstrainedBenchmark + $res.R * $res.D_L / (2.0 * $tau + 1.0)
    $rhsN_using_unconstrained_benchmark = $res.UnconstrainedBenchmark + $res.R * $res.D_N / (2.0 * $tau + 1.0)
    $wedgeInteriorFormula = $res.R * ($res.BL - $res.BN) / (2.0 * $tau + 1.0)

    [pscustomobject]@{
        Project                           = $Project.Name
        q                                 = $q
        sPM                               = $res.sPM
        UnconstrainedBenchmark            = $res.UnconstrainedBenchmark
        sL                                = $res.sL
        sN                                = $res.sN
        RHS_L_using_sPM                   = $rhsL_using_constrained_benchmark
        RHS_N_using_sPM                   = $rhsN_using_constrained_benchmark
        RHS_L_using_unconstrainedBenchmark = $rhsL_using_unconstrained_benchmark
        RHS_N_using_unconstrainedBenchmark = $rhsN_using_unconstrained_benchmark
        ActualWedge                       = $res.Wedge
        InteriorWedgeFormula              = $wedgeInteriorFormula
    }
}

function Get-ClawbackThreshold {
    param(
        [double]$rho,
        $ProjectI,
        $ProjectB,
        [double]$beta
    )

    ($ProjectI.piE_D - $ProjectB.piE_D) / ((1.0 - $rho) * $beta * ($ProjectB.Delta - $ProjectI.Delta))
}

function Get-MinimalClawback {
    param(
        [double]$q,
        $ProjectI,
        $ProjectB,
        [double]$beta
    )

    [math]::Max(0.0, 1.0 - ($ProjectI.piE_D - $ProjectB.piE_D) / ($beta * $q * ($ProjectB.Delta - $ProjectI.Delta)))
}

function Compare-GeneralDistributionShortcut {
    param(
        $Project,
        [double]$q,
        [double]$s,
        [double]$beta,
        [double]$k,
        [double]$tau
    )

    $bench = Get-PrimitiveBenchmarkObjects -Project $Project -q $q -beta $beta -k $k -tau $tau
    $cutoff = $s + ($bench.R * $bench.R) / 2.0
    $correctUniform = $cutoff * ($bench.R * $bench.BPM - ($bench.R * $bench.R) / 2.0 - $tau * $s) - ($cutoff * $cutoff) / 2.0
    $shortcut = $cutoff * ($bench.BPM - $s)

    [pscustomobject]@{
        Project        = $Project.Name
        q              = $q
        s              = $s
        Cutoff         = $cutoff
        CorrectUniform = $correctUniform
        Shortcut       = $shortcut
        Difference     = $correctUniform - $shortcut
    }
}

$beta = 0.35
$k = 0.03
$tau = 1.0

$lambdaI_L = 0.2
$lambdaE_L = 0.7
$lambdaM_L = 0.15
$kappaL = 1.0
$kappaN = 1.0

$ProjectI = Get-ProjectStats -Name 'I' -a 1.2 -sigma 0.5 -m 0.05 -etaD 0.10 -etaA 0.05 -xiD 0.12 -xiA 0.08
$ProjectB = Get-ProjectStats -Name 'B' -a 1.1 -sigma 0.3 -m 0.15 -etaD 0.08 -etaA 0.02 -xiD 0.10 -xiA 0.04
$Thresholds = Get-Thresholds -ProjectI $ProjectI -ProjectB $ProjectB -beta $beta -k $k

Show-Section 'Primitive product-market stats and thresholds'
Write-List $ProjectI
Write-List $ProjectB
Write-List $Thresholds

Show-Section 'Continuation values used to check the Section 4 figure'
$continuationGrid = @(0.0, 0.1, 0.1907549041, 0.3, 0.4461335096, 0.55, 0.6531405543, 0.8, 1.0)
$continuationRows = foreach ($q in $continuationGrid) {
    [pscustomobject]@{
        q  = $q
        RI = Get-ContinuationValue -Project $ProjectI -q $q -beta $beta -k $k
        RB = Get-ContinuationValue -Project $ProjectB -q $q -beta $beta -k $k
    }
}
Write-Table $continuationRows

Show-Section 'Derivative checks for Proposition 4'
$derivativeChecks = @(
    Compare-BenchmarkDerivative -Project $ProjectI -q 0.55 -beta $beta -k $k -tau $tau
    Compare-BenchmarkDerivative -Project $ProjectB -q 0.80 -beta $beta -k $k -tau $tau
)
Write-Table $derivativeChecks

Show-Section 'Planner-specific subsidy values used to check the Section 6 figures'
$figureGrid = @(0.0, 0.1, 0.1907549041, 0.3, 0.4461335096, 0.55, 0.6531405543, 0.8, 1.0)
$baselineFigureRows = foreach ($q in $figureGrid) {
    Get-SelectedProjectResult -q $q -ProjectI $ProjectI -ProjectB $ProjectB -Thresholds $Thresholds -beta $beta -k $k -tau $tau -lambdaI_L $lambdaI_L -lambdaE_L $lambdaE_L -lambdaM_L $lambdaM_L -kappaL $kappaL -kappaN $kappaN -UseBOnTie
}
Write-Table $baselineFigureRows

Show-Section 'Checks behind the Proposition 6 / Corollary 3 concern'
$prop6Checks = @(
    Compare-Proposition6 -Project $ProjectI -q 0.55 -beta $beta -k $k -tau $tau -lambdaI_L $lambdaI_L -lambdaE_L $lambdaE_L -lambdaM_L $lambdaM_L -kappaL $kappaL -kappaN $kappaN
    Compare-Proposition6 -Project $ProjectB -q 0.80 -beta $beta -k $k -tau $tau -lambdaI_L $lambdaI_L -lambdaE_L $lambdaE_L -lambdaM_L $lambdaM_L -kappaL $kappaL -kappaN $kappaN
)
Write-Table $prop6Checks

Show-Section 'Synthetic counterexample showing why Proposition 6 needs benchmark interiority'
$tauCounterexample = 10.0
$qCounterexample = 0.55
$constructedD = 1.5
$benchCounterexample = Get-PrimitiveBenchmarkObjects -Project $ProjectI -q $qCounterexample -beta $beta -k $k -tau $tauCounterexample
$actualPlannerInterior = [math]::Max(0.0, $benchCounterexample.UnconstrainedBenchmark + $benchCounterexample.R * $constructedD / (2.0 * $tauCounterexample + 1.0))
$claimedByProp6 = $benchCounterexample.sPM + $benchCounterexample.R * $constructedD / (2.0 * $tauCounterexample + 1.0)
$counterexampleRow = [pscustomobject]@{
    Project                       = $ProjectI.Name
    q                             = $qCounterexample
    tau                           = $tauCounterexample
    Constructed_D_p               = $constructedD
    Benchmark_Unconstrained       = $benchCounterexample.UnconstrainedBenchmark
    Benchmark_sPM                 = $benchCounterexample.sPM
    Actual_Planner_Interior_sstar = $actualPlannerInterior
    Prop6_RHS_using_sPM           = $claimedByProp6
}
Write-List $counterexampleRow

Show-Section 'Transfer-augmented wedge values used to check Appendix D sign reversal'
$signReversalRows = foreach ($q in @(0.0, 0.1907549041, 0.4461335096, 0.60, 0.6531405543, 0.70, 0.80, 1.0)) {
    $selected = Get-SelectedProjectResult -q $q -ProjectI $ProjectI -ProjectB $ProjectB -Thresholds $Thresholds -beta $beta -k $k -tau $tau -lambdaI_L $lambdaI_L -lambdaE_L $lambdaE_L -lambdaM_L $lambdaM_L -kappaL $kappaL -kappaN $kappaN -UseBOnTie -bonusBLocalApproved 0.70
    [pscustomobject]@{
        q      = $q
        Choice = $selected.Choice
        Wedge  = $selected.Wedge
    }
}
Write-Table $signReversalRows

Show-Section 'Clawback-threshold values used to check Section 7'
$clawbackRows = foreach ($rho in @(0.0, 0.1, 0.1835743071, 0.3, 0.4, 0.5, 0.6, 0.7, 0.8)) {
    [pscustomobject]@{
        rho  = $rho
        qhat = Get-ClawbackThreshold -rho $rho -ProjectI $ProjectI -ProjectB $ProjectB -beta $beta
    }
}
Write-Table $clawbackRows
Write-Output ('rhobar(q=0.8) = {0:F10}' -f (Get-MinimalClawback -q 0.8 -ProjectI $ProjectI -ProjectB $ProjectB -beta $beta))

Show-Section 'One numeric illustration of why the old Appendix B shortcut does not match the revised welfare block'
$shortcutCheck = Compare-GeneralDistributionShortcut -Project $ProjectI -q 0.55 -s 0.01 -beta $beta -k $k -tau $tau
Write-List $shortcutCheck

Show-Section 'Notes'
Write-Output '1. This script consolidates the numerical checks used in the referee report.'
Write-Output '2. The Appendix B issue was also identified by direct algebraic comparison of formulas in the TeX files, not only by numerical output.'
Write-Output '3. To rerun: powershell -ExecutionPolicy Bypass -File .\rand_buyout_project_submitready\rand_buyout_project_submitready\reproduce_referee_checks.ps1'
