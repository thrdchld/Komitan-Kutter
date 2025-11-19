#!/bin/bash

# 1. Inject Izin ke AndroidManifest.xml (Ini tetap sama)
MANIFEST="android/app/src/main/AndroidManifest.xml"
cat > $MANIFEST <<EOF
<manifest xmlns:android="http://schemas.android.com/apk/res/android"
    package="com.komitan.komitan_kutter">
    <uses-permission android:name="android.permission.READ_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.WRITE_EXTERNAL_STORAGE"/>
    <uses-permission android:name="android.permission.INTERNET"/>
    <uses-permission android:name="android.permission.MANAGE_EXTERNAL_STORAGE"/>
   
    <application
        android:label="Komitan Kutter"
        android:name="\${applicationName}"
        android:icon="@mipmap/ic_launcher">
        <activity
            android:name=".MainActivity"
            android:exported="true"
            android:launchMode="singleTop"
            android:theme="@style/LaunchTheme"
            android:configChanges="orientation|keyboardHidden|keyboard|screenSize|smallestScreenSize|locale|layoutDirection|fontScale|screenLayout|density|uiMode"
            android:hardwareAccelerated="true"
            android:windowSoftInputMode="adjustResize">
            <meta-data
              android:name="io.flutter.embedding.android.NormalTheme"
              android:resource="@style/NormalTheme"
              />
            <intent-filter>
                <action android:name="android.intent.action.MAIN"/>
                <category android:name="android.intent.category.LAUNCHER"/>
            </intent-filter>
        </activity>
        <meta-data
            android:name="flutterEmbedding"
            android:value="2" />
    </application>
</manifest>
EOF

# 2. [UPDATE] Inject minSdk 24 ke build.gradle.kts (Kotlin Script)
APP_GRADLE_KTS="android/app/build.gradle.kts"

# Ubah minSdk = flutter.minSdkVersion menjadi 24
sed -i 's/minSdk = flutter.minSdkVersion/minSdk = 24/' $APP_GRADLE_KTS

# Atau jika formatnya berbeda, cari angka default dan ubah
sed -i 's/minSdk = [0-9]*/minSdk = 24/' $APP_GRADLE_KTS

echo "✅ Konfigurasi berhasil di-update untuk format KTS!"