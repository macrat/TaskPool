import-module .\TaskPool.psd1


Describe "TaskPool" {
    It "serial run" {
        $result = [PSCustomObject]@{
            Log = @()
            Error = 0
        }

        $pool = New-TPTaskPool `
            -NumSlots 1 `
            -OnTaskComplete {
                $result.Log += $_.Result
            }.GetNewClosure() `
            -OnTaskError {
                Write-Error $_.Error
                $result.Error += 1
            }.GetNewClosure()

        foreach ($i in 1..10) {
            Add-TPTask $pool {
                $Args[0] * 2
            } -Arguments $i
        }

        $pool.Run()

        $result.Error | Should Be 0
        $result.Log.Count | Should Be 10
        $result.Log -join "," | Should Be ((1..10 | foreach { $_ * 2 }) -join ",")
    }

    It "parallel run" {
        $result = [PSCustomObject]@{
            Sum = 0
            Error = 0
        }
        $pool = New-TPTaskPool `
            -NumSlots 5 `
            -OnTaskComplete {
                $result.Sum += [int]$_.Result
            }.GetNewClosure() `
            -OnTaskError {
                Write-Error $_.Error
                $result.Error += 1
            }.GetNewClosure()

        foreach ($i in 1..10) {
            Add-TPTask $pool -Name "Task $i" -Arguments $i -Action {
                $Args[0] * 2
            }
        }

        $pool.Run()

        $result.Error | Should Be 0
        $result.Sum | Should Be (1..10 | foreach -begin { $s = 0} -process { $s += $_ * 2 } -end { $s })
    }

    It "retry task" {
        $result = [PSCustomObject]@{
            Complete = 0
            Error = 0
        }
        $pool = New-TPTaskPool `
            -NumSlots 50 `
            -OnTaskComplete {
                $result.Complete += 1
            }.GetNewClosure() `
            -OnTaskError {
                $result.Error += 1
            }.GetNewClosure()

        foreach ($i in 1..100) {
            Add-TPTask $pool {
                if ((Get-Random -min 1 -max 10) -eq 1) {
                    throw "something error"
                }
            }
        }

        $pool.Run()

        $result.Error | Should BeGreaterThan 0
        $result.Error | Should BeLessThan 1000
        $result.Complete | Should Be 100
    }

    It "max retry" {
        $result = [PSCustomObject]@{
            Complete = 0
            Error = 0
        }
        $pool = New-TPTaskPool `
            -OnTaskComplete {
                $result.Complete += 1
            }.GetNewClosure() `
            -OnTaskError {
                $result.Error += 1
            }.GetNewClosure()

        Add-TPTask $pool {
            throw "always error"
        } -MaxRetry 5
        Add-TPTask $pool {
            throw "always error"
        } -MaxRetry 3

        $pool.Run()

        $result.Complete | Should Be 0
        $result.Error | Should Be 10  # (1 + 5) + (1 + 3)
    }

    It "no retry" {
        $result = [PSCustomObject]@{
            Complete = 0
            Error = 0
        }
        $pool = New-TPTaskPool `
            -OnTaskComplete {
                $result.Complete += 1
            }.GetNewClosure() `
            -OnTaskError {
                $result.Error += 1
            }.GetNewClosure()

        Add-TPTask -Name "fail-task" $pool -MaxRetry 0 -Action {
            throw "always error"
        }

        $pool.Run()

        $result.Complete | Should Be 0
        $result.Error | Should Be 1
    }

    It "dynamic create task" {
        $task = {
            param([int]$count)

            if ($count -lt 5) {
                @{
                    Name = "task${count}"
                    Arguments = $count + 1
                }
            } else {
                $null
            }
        }

        $result = [PSCustomObject]@{
            Complete = 0
            Error = 0
        }
        $pool = New-TPTaskPool `
            -OnTaskError {
                Write-Error $_.Error
                $result.Error += 1
            }.GetNewClosure()

        $pool.OnTaskComplete.Add({
            $result.Complete += 1
            if ($_.Result -ne $null) {
                Add-TPTask $pool $task -Name $_.Result.Name -Arguments $_.Result.Arguments
            }
        }.GetNewClosure())

        Add-TPTask $pool $task -Name "task1" -Arguments @(1)

        $pool.Run()

        $result.Error | Should Be 0
        $result.Complete | Should Be 5
    }
}


Describe "New-TaskPool" {
    It "num slots" {
        (New-TPTaskPool).NumSlots | Should Be 3
        (New-TPTaskPool -NumSlots 2).NumSlots | Should Be 2
        (New-TPTaskPool -NumSlots 0).NumSlots | Should Be 1
        (New-TPTaskPool -NumSlots -1).NumSlots | Should Be 1
    }

    It "OnTaskComplete" {
        $cb = {}
        $cb2 = {}

        $pool = (New-TPTaskPool -OnTaskComplete $cb).OnTaskComplete
        $pool.Count | Should Be 1
        $pool.Handlers[0] | Should Be $cb

        $pool = (New-TPTaskPool -OnTaskComplete @($cb, $cb, $cb)).OnTaskComplete
        $pool.Count | Should Be 1
        $pool.Handlers[0] | Should Be $cb

        $pool = (New-TPTaskPool -OnTaskComplete @($cb, $cb2)).OnTaskComplete
        $pool.Count | Should Be 2
        $cb  -In $pool.Handlers | Should Be $True
        $cb2 -In $pool.Handlers | Should Be $True
    }

    It "OnTaskError" {
        $cb = {}
        $cb2 = {}

        $pool = (New-TPTaskPool -OnTaskError $cb).OnTaskError
        $pool.Count | Should Be 1
        $pool.Handlers[0] | Should Be $cb

        $pool = (New-TPTaskPool -OnTaskError @($cb, $cb, $cb)).OnTaskError
        $pool.Count | Should Be 1
        $pool.Handlers[0] | Should Be $cb

        $pool = (New-TPTaskPool -OnTaskError @($cb, $cb2)).OnTaskError
        $pool.Count | Should Be 2
        $cb  -In $pool.Handlers | Should Be $True
        $cb2 -In $pool.Handlers | Should Be $True
    }
}


Describe "Add-Task" {
    It "given task name" {
        $pool = New-TPTaskPool

        (Add-TPTask $pool {} -Name "hello world!").Name | Should Be "hello world!"
    }

    It "generate task name" {
        $pool = New-TPTaskPool

        foreach ($i in 1..10) {
            (Add-TPTask $pool {}).Name | Should Match "TaskPool_[0-9A-Z]{8}"
        }
    }
}
