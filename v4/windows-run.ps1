# Windows용 Blue-Green 배포 시스템 실행 스크립트
param(
    [switch]$Clean,
    [switch]$Build,
    [switch]$Run,
    [switch]$Stop,
    [switch]$Logs
)

$ErrorActionPreference = "Stop"

# 색상 함수
function Write-ColorOutput($ForegroundColor) {
    $fc = $host.UI.RawUI.ForegroundColor
    $host.UI.RawUI.ForegroundColor = $ForegroundColor
    if ($args) {
        Write-Output $args
    }
    else {
        $input | Write-Output
    }
    $host.UI.RawUI.ForegroundColor = $fc
}

function Write-Green { Write-ColorOutput Green $args }
function Write-Red { Write-ColorOutput Red $args }
function Write-Yellow { Write-ColorOutput Yellow $args }
function Write-Blue { Write-ColorOutput Blue $args }

# v4 디렉터리로 이동
$v4Path = "C:\Users\zkvpt\Desktop\bgTest\v4"
if (!(Test-Path $v4Path)) {
    Write-Red "❌ v4 디렉터리를 찾을 수 없습니다: $v4Path"
    exit 1
}
Set-Location $v4Path

# Docker 상태 확인
try {
    docker version | Out-Null
} catch {
    Write-Red "❌ Docker가 실행 중이지 않습니다. Docker Desktop을 시작해주세요."
    exit 1
}

if ($Clean) {
    Write-Yellow "🧹 기존 컨테이너 및 이미지 정리 중..."
    docker stop blue-green-nginx 2>$null
    docker rm blue-green-nginx 2>$null
    docker rmi bgtest-blue-green-deployment 2>$null
    docker system prune -f
    Write-Green "✅ 정리 완료"
}

if ($Build) {
    Write-Yellow "🔨 Docker 이미지 빌드 중..."
    docker build -t bgtest-blue-green-deployment .
    if ($LASTEXITCODE -eq 0) {
        Write-Green "✅ 빌드 성공"
    } else {
        Write-Red "❌ 빌드 실패"
        exit 1
    }
}

if ($Run) {
    Write-Yellow "🚀 컨테이너 실행 중..."
    docker-compose up -d
    
    if ($LASTEXITCODE -eq 0) {
        Write-Green "✅ 컨테이너 시작됨"
        Start-Sleep -Seconds 5
        
        Write-Blue "📊 컨테이너 상태:"
        docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"
        
        Write-Blue "🌐 접속 URL:"
        Write-Output "  - 메인 서비스:     http://localhost"
        Write-Output "  - 관리자 페이지:   http://localhost:8080"
        Write-Output "  - Blue 서버:      http://localhost/blue"
        Write-Output "  - Green 서버:     http://localhost/green"
        Write-Output "  - 상태 확인:      http://localhost/status"
    } else {
        Write-Red "❌ 컨테이너 시작 실패"
        exit 1
    }
}

if ($Stop) {
    Write-Yellow "⏹️ 컨테이너 중지 중..."
    docker-compose down
    Write-Green "✅ 컨테이너 중지됨"
}

if ($Logs) {
    Write-Blue "📋 컨테이너 로그:"
    docker-compose logs -f
}

if (!$Clean -and !$Build -and !$Run -and !$Stop -and !$Logs) {
    Write-Blue "사용법:"
    Write-Output "  ./windows-run.ps1 -Clean          # 기존 컨테이너/이미지 정리"
    Write-Output "  ./windows-run.ps1 -Build          # Docker 이미지 빌드"
    Write-Output "  ./windows-run.ps1 -Run            # 컨테이너 실행"
    Write-Output "  ./windows-run.ps1 -Stop           # 컨테이너 중지"
    Write-Output "  ./windows-run.ps1 -Logs           # 로그 확인"
    Write-Output ""
    Write-Green "전체 프로세스:"
    Write-Output "  ./windows-run.ps1 -Clean -Build -Run"
}