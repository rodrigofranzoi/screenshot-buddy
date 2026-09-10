# Store Copy — Capture Buddy

Supported locales: `en`, `de`, `nl`, `pt`, `es`, `fr`, `it`, `ar`, `zh`, `ru`, `ja`.

## App Store Connect — naming (Guideline 5.2.5)

**Use exactly:** `Capture Buddy`  
**Do not use:** `Screenshot Buddy`, `Screenshot Buddy for Mac`, `Capture Buddy for Mac`, `… for macOS`, or any name that includes Apple product terms (`Mac`, `macOS`, `iPhone`, etc.).

Binary display name (`CFBundleDisplayName` / `CFBundleName`) is `Capture Buddy`. Keep App Store Connect **Name** and on-device name aligned — never append “for Mac”. Bundle ID stays `com.buddy.screenshot`.

## Legal URLs (App Store Connect)

- App Store ID: `6809226358`
- Privacy: https://rodrigofranzoi.github.io/screenshot-buddy/privacy.html
- Terms: https://rodrigofranzoi.github.io/screenshot-buddy/terms.html
- Rate / write review: https://apps.apple.com/app/id6809226358?action=write-review

## What's New (all locales)

Initial release.

---

## App Review Notes (Apple)

Paste into App Store Connect → App Review Information → Notes.

```
Capture Buddy is a macOS menu-bar (agent) app. There is no Dock icon by default (LSUIElement).

NO LOGIN / DEMO ACCOUNT REQUIRED.

Launch at login: OFF by default. On first launch the app opens the main window and shows a consent popup (Not Now / Open at Login).
It only registers as a Login Item if the user chooses Open at Login. Later launches stay menu-bar only. Change anytime in Settings → Preferences → Startup (Guideline 2.4.5(iii)).

How to review:
1. Launch the app. Look for the camera.viewfinder icon in the macOS menu bar.
2. Click the menu bar icon to open the recent-shots popover.
3. Choose Open to show the main gallery window (or open from the popover controls).
4. Add sample images: take a screenshot (⌘⇧3 / ⌘⇧4), copy an image and Paste, or drag & drop into the gallery.
5. Select a shot to open the editor: annotate (draw / arrow / text), crop, blur, black-box, OCR copy, color pick, QR scan, and Auto-blur for detected secrets.
6. Sensitive items may appear blurred. Reveal with Touch ID or the Mac login password (LocalAuthentication). Unlock lasts ~10 minutes.
7. Settings (gear): history limits, privacy/blur tags, pause capture, optional launch at login.

Permissions / entitlements:
- App Sandbox enabled.
- Pictures folder read/write (and user-granted access to Desktop / custom screenshot save folder).
- User-selected file access for Save As / import / screenshot-folder bookmark.
- Network client: Firebase Analytics & Crashlytics only.

Privacy:
- Screenshot images, notes, and OCR text stay on device (UserDefaults). Never uploaded.
- Analytics/Crashlytics do not include screenshot or clipboard payloads.
- On-device policy blocks pornography / sexual content from import and copy.
- Export compliance: exempt — HTTPS/TLS only (ITSAppUsesNonExemptEncryption = false).

Contact: use the App Store Connect account owner email if anything is unclear.
```

---

## TestFlight Notes

### Beta App Description

Paste into TestFlight → Test Information → Beta App Description.

```
Capture Buddy keeps your macOS screenshots in a searchable gallery with a fast editor, one-tap auto-blur for secrets, OCR, color pick, QR scan, and Touch ID for sensitive previews — plus recent shots in the menu bar.
```

### What to Test

Paste into TestFlight → Test Information → What to Test.

```
Thanks for testing Capture Buddy!

Please try:
• Menu bar icon → recent shots popover → Open gallery
• Capture with ⌘⇧3 / ⌘⇧4 (or paste / drop an image into the gallery)
• Editor: draw, arrow, text, crop, blur, black-box
• Auto-blur on a shot that contains a fake password / IBAN / card number
• Smart tools: OCR copy text, pick a hex color, scan a QR code
• Unlock a blurred sensitive preview with Touch ID or your Mac password
• Pause capture from the menu bar, then resume
• Save As / copy to clipboard / delete a shot
• Settings: history limits and which sensitive types require unlock

Report crashes, localization issues, and anything confusing in the gallery or editor.

No account needed. All screenshot data stays on your Mac.
```

### Beta App Review (TestFlight)

Same content as **App Review Notes** above if Apple requests Beta App Review Information. No demo account.

---

## English (`en`)

**Name:** Capture Buddy  
**Subtitle:** Screenshots Manager  
**Keywords:** screenshot,capture,annotate,blur,redact,editor,menu bar,OCR,QR,search  
**Promotional Text:** History, edit, redact & organize every shot. Auto-blur secrets, OCR, color pick, QR scan, and Touch ID for sensitive previews — gallery + menu bar.

**Description:**

Capture Buddy keeps every capture in a searchable gallery — import, paste, or drop shots in. The fast editor covers draw, arrows, text, crop, blur, and black-box.

It detects likely passwords, IBANs, cards, and other sensitive patterns so you can auto-blur in one tap. Copy text with OCR, pick hex colors, and scan every QR in a shot.

Save As, overwrite, or copy back to the clipboard. Recent shots live in the menu bar. Pause capture when you need privacy. Sensitive previews stay locked until Touch ID or your password. Built for macOS accessibility.

---

## German (`de`)

**Name:** Capture Buddy  
**Subtitle:** Screenshot-Manager  
**Keywords:** Screenshot,Aufnahme,annotieren,unscharf,schwärzen,Editor,Menüleiste,OCR,QR,Suche  
**Promotional Text:** Bearbeiten, schwärzen und organisieren. Auto-Unschärfe für Geheimnisse, OCR, Farbpipette, QR-Scan und Touch ID für sensible Vorschauen — Galerie + Menüleiste.

**Description:**

Capture Buddy speichert jede Aufnahme in einer durchsuchbaren Galerie — importieren, einfügen oder per Drag & Drop. Der schnelle Editor bietet Zeichnen, Pfeile, Text, Zuschneiden, Unschärfe und Schwärzen.

Er erkennt wahrscheinliche Passwörter, IBANs, Karten und andere sensible Muster, damit Sie sie mit einem Tipp automatisch unscharf machen können. Text per OCR kopieren, Hex-Farben aufnehmen und jeden QR im Bild scannen.

Speichern unter, überschreiben oder zurück in die Zwischenablage. Aktuelle Aufnahmen in der Menüleiste. Pausieren Sie die Aufnahme, wenn Sie Privatsphäre brauchen. Sensible Vorschauen bleiben bis Touch ID oder Passwort gesperrt. Für macOS-Bedienungshilfen gebaut.

---

## Dutch (`nl`)

**Name:** Capture Buddy  
**Subtitle:** Screenshotmanager  
**Keywords:** screenshot,schermafbeelding,annoteren,vervagen,redactie,editor,menubalk,OCR,QR,zoeken  
**Promotional Text:** Bewerk, redacteer en organiseer elke shot. Auto-vervagen van geheimen, OCR, kleurenkiezer, QR-scan en Touch ID voor gevoelige previews — galerij + menubalk.

**Description:**

Capture Buddy bewaart al je captures in een doorzoekbare galerij — importeer, plak of sleep shots erin. De snelle editor biedt tekenen, pijlen, tekst, bijsnijden, vervagen en zwartmaken.

Het detecteert waarschijnlijke wachtwoorden, IBANs, kaarten en andere gevoelige patronen zodat je met één tik automatisch kunt vervagen. Kopieer tekst met OCR, kies hex-kleuren en scan elke QR in een shot.

Opslaan als, overschrijven of terugkopiëren naar het klembord. Recente shots zitten in de menubalk. Pauzeer vastleggen wanneer je privacy nodig hebt. Gevoelige previews blijven vergrendeld tot Touch ID of je wachtwoord. Gebouwd voor macOS-toegankelijkheid.

---

## Portuguese (`pt`)

**Name:** Capture Buddy  
**Subtitle:** Gestor de capturas  
**Keywords:** screenshot,captura,anotar,desfoque,redação,editor,barra de menus,OCR,QR,pesquisa  
**Promotional Text:** Edite, redija e organize cada captura. Desfoque automático, OCR, seletor de cor, QR e Touch ID para pré-visualizações sensíveis — galeria + barra de menus.

**Description:**

O Capture Buddy guarda cada captura numa galeria pesquisável — importe, cole ou largue shots. O editor rápido inclui desenho, setas, texto, recorte, desfoque e caixa preta.

Deteta passwords, IBANs, cartões e outros padrões sensíveis para desfocar automaticamente com um toque. Copie texto com OCR, escolha cores hex e leia cada QR na captura.

Guardar como, substituir ou copiar de volta para a área de transferência. Capturas recentes na barra de menus. Pause a captura quando precisar de privacidade. Pré-visualizações sensíveis ficam bloqueadas até Touch ID ou a sua password. Feito para acessibilidade no macOS.

---

## Spanish (`es`)

**Name:** Capture Buddy  
**Subtitle:** Gestor de capturas  
**Keywords:** captura,screenshot,anotar,desenfoque,redacción,editor,barra de menús,OCR,QR,buscar  
**Promotional Text:** Edita, redacta y organiza cada captura. Desenfoque automático, OCR, selector de color, QR y Touch ID para vistas previas sensibles — galería + barra de menús.

**Description:**

Capture Buddy guarda cada captura en una galería buscable — importa, pega o suelta capturas. El editor rápido incluye dibujo, flechas, texto, recorte, desenfoque y caja negra.

Detecta contraseñas, IBAN, tarjetas y otros patrones sensibles para desenfocar automáticamente con un toque. Copia texto con OCR, elige colores hex y escanea cada QR de la captura.

Guardar como, sobrescribir o copiar al portapapeles. Capturas recientes en la barra de menús. Pausa la captura cuando necesites privacidad. Las vistas previas sensibles permanecen bloqueadas hasta Touch ID o tu contraseña. Pensado para la accesibilidad de macOS.

---

## French (`fr`)

**Name:** Capture Buddy  
**Subtitle:** Gestionnaire de captures  
**Keywords:** capture,screenshot,annoter,flou,rédaction,éditeur,barre de menus,OCR,QR,recherche  
**Promotional Text:** Éditez, masquez et organisez chaque capture. Flou auto des secrets, OCR, pipette, scan QR et Touch ID pour les aperçus sensibles — galerie + barre de menus.

**Description:**

Capture Buddy regroupe toutes vos captures dans une galerie consultable — importez, collez ou déposez des shots. L’éditeur rapide couvre dessin, flèches, texte, recadrage, flou et cadre noir.

Il détecte mots de passe, IBAN, cartes et autres motifs sensibles pour flouter automatiquement en un tap. Copiez du texte via OCR, prélevez des couleurs hex et scannez chaque QR.

Enregistrer sous, écraser ou recopier dans le presse-papiers. Captures récentes dans la barre de menus. Mettez la capture en pause quand vous avez besoin d’intimité. Les aperçus sensibles restent verrouillés jusqu’à Touch ID ou votre mot de passe. Conçu pour l’accessibilité macOS.

---

## Italian (`it`)

**Name:** Capture Buddy  
**Subtitle:** Gestore di screenshot  
**Keywords:** screenshot,cattura,annotare,sfocatura,redazione,editor,barra dei menu,OCR,QR,cerca  
**Promotional Text:** Modifica, redigi e organizza ogni scatto. Auto-sfocatura dei segreti, OCR, selettore colore, scansione QR e Touch ID per anteprime sensibili — galleria + barra dei menu.

**Description:**

Capture Buddy conserva ogni cattura in una galleria ricercabile — importa, incolla o trascina gli scatti. L’editor veloce include disegno, frecce, testo, ritaglio, sfocatura e riquadro nero.

Rileva password, IBAN, carte e altri pattern sensibili per sfocare automaticamente con un tocco. Copia testo con OCR, preleva colori esadecimali e scansiona ogni QR.

Salva con nome, sovrascrivi o ricopia negli appunti. Scatti recenti nella barra dei menu. Metti in pausa l’acquisizione quando ti serve privacy. Le anteprime sensibili restano bloccate fino a Touch ID o password. Pensato per l’accessibilità di macOS.

---

## Arabic (`ar`)

**Name:** Capture Buddy  
**Subtitle:** مدير لقطات الشاشة  
**Keywords:** لقطة شاشة,تحرير,تمويه,حجب,محرر,شريط القوائم,OCR,QR,بحث  
**Promotional Text:** عدّل واحجب ونظّم كل لقطة. تمويه تلقائي للأسرار وOCR والتقاط الألوان ومسح QR وTouch ID للمعاينات الحساسة — المعرض + شريط القوائم.

**Description:**

يحفظ Capture Buddy كل لقطة في معرض قابل للبحث — استورد أو الصق أو أفلت اللقطات. يمنحك المحرر السريع رسمًا وأسهمًا ونصًا وقصًا وتمويهًا وصندوقًا أسود.

يكتشف كلمات المرور وIBAN والبطاقات وأنماطًا حساسة أخرى لتمويهها تلقائيًا بنقرة واحدة. انسخ النص بـ OCR والتقط ألوان hex وامسح كل رمز QR في اللقطة.

احفظ باسم أو استبدل أو انسخ إلى الحافظة. اللقطات الأخيرة في شريط القوائم. أوقف الالتقاط مؤقتًا عندما تحتاج إلى الخصوصية. تبقى المعاينات الحساسة مقفلة حتى Touch ID أو كلمة المرور. مصمم لإمكانية الوصول على macOS.

---

## Chinese Simplified (`zh`)

**Name:** Capture Buddy  
**Subtitle:** 截图管理器  
**Keywords:** 截图,批注,模糊,遮挡,编辑器,菜单栏,OCR,二维码,搜索  
**Promotional Text:** 编辑、遮挡并整理每张截图。自动模糊敏感信息，OCR、取色、扫二维码，以及 Touch ID 解锁敏感预览——图库 + 菜单栏。

**Description:**

Capture Buddy 将每张截图保存在可搜索的图库中——支持导入、粘贴或拖放。快速编辑器提供绘制、箭头、文字、裁剪、模糊与黑框。

可检测密码、IBAN、银行卡等敏感内容，一键自动模糊。用 OCR 复制文字，拾取十六进制颜色，并扫描截图中的每个二维码。

另存为、覆盖或重新复制到剪贴板。最近截图就在菜单栏。需要隐私时可暂停捕获。敏感预览在 Touch ID 或密码解锁前保持锁定。为 macOS 辅助功能而打造。

---

## Russian (`ru`)

**Name:** Capture Buddy  
**Subtitle:** Менеджер скриншотов  
**Keywords:** скриншот,снимок,разметка,размытие,редактор,меню,OCR,QR,поиск  
**Promotional Text:** Правьте, маскируйте и упорядочивайте каждый снимок. Авторазмытие секретов, OCR, пипетка, QR и Touch ID для скрытых превью — галерея + меню.

**Description:**

Capture Buddy хранит все снимки в удобной галерее с поиском — импорт, вставка или перетаскивание. Быстрый редактор: рисование, стрелки, текст, обрезка, размытие и чёрный блок.

Находит пароли, IBAN, карты и другие чувствительные шаблоны — авторазмытие в один тап. Копируйте текст через OCR, берите hex-цвета и сканируйте каждый QR на снимке.

«Сохранить как», перезаписать или скопировать обратно в буфер. Недавние снимки — в меню. Приостановите захват, когда нужна приватность. Скрытые превью остаются под защитой Touch ID или пароля. Сделано с учётом доступности macOS.

---

## Japanese (`ja`)

**Name:** Capture Buddy  
**Subtitle:** スクリーンショット管理  
**Keywords:** スクリーンショット,注釈,ぼかし,墨消し,エディタ,メニューバー,OCR,QR,検索  
**Promotional Text:** すべてのショットを編集・墨消し・整理。秘密の自動ぼかし、OCR、カラーピッカー、QR 読み取り、機密プレビューの Touch ID — ギャラリー＋メニューバー。

**Description:**

Capture Buddy はすべてのショットを検索可能なギャラリーに保存し、インポート・ペースト・ドロップに対応。描画・矢印・テキスト・切り抜き・ぼかし・黒塗りができる高速エディタを提供します。

パスワードや IBAN、カードなどの機密パターンを検出し、ワンタップで自動ぼかし。OCR でテキストをコピーし、HEX カラーを取得、ショット内の QR もすべて読み取ります。

別名で保存、上書き、またはクリップボードへ再コピー。最近のショットはメニューバーに。プライバシーが必要なときはキャプチャを一時停止。機密プレビューは Touch ID またはパスワード解除までロック。macOS のアクセシビリティに配慮して設計されています。

---

## Google Play

N/A — macOS only.
