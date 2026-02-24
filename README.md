# Controller Tablet

전시용 태블릿 컨트롤러 앱

## APK 빌드

```bash
flutter build apk --release
```

빌드 결과: `build/app/outputs/flutter-apk/app-release.apk`

## 설치 및 업데이트

### 최초 설치

```bash
# 1. APK 설치
adb install build/app/outputs/flutter-apk/app-release.apk

# 2. Device Owner 등록 (키오스크 모드용)
adb shell dpm set-device-owner com.example.controller_tablet/.AdminReceiver
```

### 업데이트

```bash
adb install build/app/outputs/flutter-apk/app-release.apk
```

서명 키가 동일하므로 덮어쓰기 설치됩니다. Device Owner 재등록 불필요.

## 키오스크 모드 (Device Owner)

### 사전 준비

- 태블릿에서 **모든 구글 계정 삭제** (설정 → 계정)
- **USB 디버깅** 활성화 (설정 → 개발자 옵션)

### 등록

```bash
adb shell dpm set-device-owner com.example.controller_tablet/.AdminReceiver
```

### 해제

```bash
adb shell dpm remove-active-admin com.example.controller_tablet/.AdminReceiver
```

## UDP 명령어

| 명령 | 용도 |
|------|------|
| O | IDLE → Ready 진입 |
| I | IDLE 복귀 (수동) |
| N | 모터 ON (Play 시작) |
| F | 모터 OFF (Play 종료) |
| J | IDLE 복귀 (타이머 만료) |

## 서명 키

- 키 파일: `android/app/upload-keystore.jks`
- 설정 파일: `android/key.properties`
- 비밀번호: `steady123`

맥/윈도우 어디서 빌드해도 동일한 서명으로 APK 생성됨.
