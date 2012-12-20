<#
Starting SAP systems
Version : 0.1
Prerequisite : performing as user <sid>adm
#>

##### 変数定義 #####

# 以下の変数を定義してください

# 0:実行ユーザ確認なし, 1:実行ユーザが<sid>admかcloudinitserviceかを確認する
$checkuser = 1

# SAPインスタンス向けサービス以外で、起動が必要なサービス
$NonSAPService = @("MSSQLSERVER","SQLSERVERAGENT","SQLWriter","MSSQLFDLauncher")
$SubSAPService = @("SAPHostControl")


# 以下は変更しないでください


# SAPインスタンス向けサービス名の取得
$SAPService = get-service -Name "SAP???_??" | % {$_.Name}
# 起動するサービスの数
$SAPSrvCount = $SAPService.count
$NonSAPSrvCount = $NonSAPService.count
$SubSAPSrvCount = $SubSAPService.count

# その他の変数定義
$SCRIPT_PATH = Split-Path -Path $MyInvocation.MyCommand.Definition -Parent
$LOGFILE_PATH = $SCRIPT_PATH + "\log"
$SCRIPT_ID =  $MyInvocation.MyCommand.Name
$LOGFILE = $LOGFILE_PATH + "\" + $SCRIPT_ID.Replace(".ps1",".log")
$HOST_NAME = hostname
# ERROR_LEVELの定義
# 1:許可されていない実行ユーザで実行している
# 2:サービス起動に失敗した
# 3:SAPインスタンス起動に失敗した
$ERROR_LEVEL = 0


##### 関数定義 #####

# サービスを起動する
function StartService ($ServCount, $ServName) {
    for ( $i = 0; $i -lt $ServCount; $i++ ) {
        $Service = Get-Service $($ServName[$i])
        if ( $Service.Status -eq "Running" ) {
            "$($ServName[$i])サービスは既に起動しているので、起動処理をスキップします。" >> $LOGFILE 2>&1
        } else {
            Start-Service $($ServName[$i]) >> $LOGFILE 2>&1
            $Service = Get-Service $($ServName[$i])
            if ( $Service.Status -ne "Running" ) {
                $ERROR_MSG = "$($ServName[$i])サービスの起動に失敗しました。"
                $ERROR_LEVEL = 2
                break Root
            }
        }
    }
}

# SAPインスタンスを起動する
# 30分(1800秒)経過しても完全に起動しなければ、タイムアウトとして処理する
function Exec_sapcontrol ($No, $Msg, $wt=1800, $dt=5) {
    "${SAPEXE}\sapcontrol.exe -nr $No -prot PIPE -function StartWait $wt $dt" >> $LOGFILE 2>&1
    & "${SAPEXE}\sapcontrol.exe" -nr $No -prot PIPE -function StartWait $wt $dt >> $LOGFILE 2>&1
    if ( $LASTEXITCODE -ne 0 ) {
        $ERROR_MSG = "${Msg}インスタンスの起動に失敗しました。"
        $ERROR_LEVEL = 3
        break Root
    }
}


##### SAP起動処理開始 #####

$STEP_NAME = "INIT"

New-Item $LOGFILE_PATH -itemType Directory -Force | Out-Null

$DATE = Get-Date -format G
"****************************************"   >> $LOGFILE 2>&1
"* START        : ${SCRIPT_PATH}\$SCRIPT_ID" >> $LOGFILE 2>&1
"* DATE         : $DATE"                     >> $LOGFILE 2>&1
"* ComputerName : $HOST_NAME"                >> $LOGFILE 2>&1
"****************************************"   >> $LOGFILE 2>&1

# SAPのインスタンス番号やSIDを抽出する
# SIDs[$i] = SID , $***No = インスタンス番号
# AdmUser = <sid>adm と cloudinitservice が入る
$SIDs = get-childitem HKLM:\SOFTWARE\SAP | ? {$_.property -eq "AdmUser"} | % {$_.Name}
$regpath = $SIDs -replace "HKEY_LOCAL_MACHINE\\","HKLM:"
$AdmUser = get-itemproperty $regpath | % {$_.AdmUser}
$AdmUser += $(hostname) + "\cloudinitservice"
$SIDsCount = $SIDs.Count
for ( $i = 0; $i -lt $SIDsCount; $i++ ) {
    $SIDs[$i] = $SIDs[$i].SubString($SIDs[$i].Length-3,3)
    $SCSname = Get-ChildItem ( join-path "\\localhost\sapmnt\" $SIDs[$i] ) | ? {$_.Name -like "*SCS*"} | % {$_.Name}
    if ( $SCSname -ne $null ) {
        $SCSNo =  $SCSname.SubString($SCSname.Length-2,2)
        $SCSMsg = "SCS"
    }
    $CIname = Get-ChildItem ( join-path "\\localhost\sapmnt\" $SIDs[$i] ) | ? {$_.Name -like "DVEBMGS*"} | % {$_.Name}
    if ( $CIname -ne $null ) {
        $CINo =  $CIname.SubString($CIname.Length-2,2)
        $CIMsg = "セントラル"
        # CIのsapcontrolを使うので、そのパスを$SAPEXEに入れておく。
        $SAPEXE = "\\localhost\sapmnt\" + $SIDs[$i] + "\SYS\exe\uc\NTAMD64"
    }
    $DAAname = Get-ChildItem ( join-path "\\localhost\sapmnt\" $SIDs[$i] ) | ? {$_.Name -like "SMDA*"} | % {$_.Name}
    if ( $DAAname -ne $null ) {
        $DAANo =  $DAAname.SubString($DAAname.Length-2,2)
        $DAAMsg = "DAA"
    }
}

:Root While(1) {

    if ( $checkuser -eq 1 ) {
        if ( $AdmUser -notcontains $(whoami) ) {
            $ERROR_MSG = "このスクリプトは、以下のいずれかのユーザで実行する必要があります。ログオンし直して再実行してください。$AdmUser" >> $LOGFILE 2>&1
            $ERROR_LEVEL = 1
            break Root
        }
        "実行ユーザ確認OK。" >> $LOGFILE 2>&1
    } else {
        "実行ユーザ確認をスキップします。" >> $LOGFILE 2>&1
    }

    cd $LOGFILE_PATH

    $STEP_NAME = "START_NonSAPService"
    if ( $NonSAPSrvCount -gt 0 ) {
        StartService $NonSAPSrvCount $NonSAPService
    }
    
    $STEP_NAME = "START_SAPService (exclude instance service)"
    if ( $SubSAPSrvCount -gt 0 ) {
        StartService $SubSAPSrvCount $SubSAPService
    }

    $STEP_NAME = "START_SAPService"
    if ( $SAPSrvCount -gt 0 ) {
        StartService $SAPSrvCount $SAPService
    }

# サービス起動後すぐにSAPインスタンス起動すると失敗する時があるので3秒程度待機する
    ping -n 3 localhost | Out-Null

    $STEP_NAME = "START_SAPInstances"

    if ( $SCSNo -ne $null ) {
        Exec_sapcontrol $SCSNo $SCSMsg
    }
    if ( $CINo -ne $null ) {
        Exec_sapcontrol $CINo $CIMsg
    }
    if ( $DAANo -ne $null ) {
        Exec_sapcontrol $DAANo $DAAMsg
    }
   
    break Root
} # Root-End


##### 終了処理 #####

# 正常終了の場合
$DATE = Get-Date -format G
if ( $ERROR_LEVEL -eq 0 ) {
    "****************************************"   >> $LOGFILE 2>&1
    "* NORMAL END   : ${SCRIPT_PATH}\$SCRIPT_ID" >> $LOGFILE 2>&1
    "* DATE         : $DATE"                     >> $LOGFILE 2>&1
    "* ComputerName : $HOST_NAME"                >> $LOGFILE 2>&1
    "****************************************"   >> $LOGFILE 2>&1

} else {

# 異常終了の場合
    "****************************************"   >> $LOGFILE 2>&1
    "* ERROR END    : ${SCRIPT_PATH}\$SCRIPT_ID" >> $LOGFILE 2>&1
    "* DATE         : $DATE"                     >> $LOGFILE 2>&1
    "* ComputerName : $HOST_NAME"                >> $LOGFILE 2>&1
    "* ERROR STEP   : $STEP_NAME"                >> $LOGFILE 2>&1
    "* ERROR LEVEL  : $ERROR_LEVEL"              >> $LOGFILE 2>&1
    "* ERROR MESSAGE: $ERROR_MSG"                >> $LOGFILE 2>&1
    "****************************************"   >> $LOGFILE 2>&1
}

exit $ERROR_LEVEL
