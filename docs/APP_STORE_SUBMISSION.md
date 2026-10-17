# PDFview - Apple App Store 上架完整资料与准备手册

> **应用状态**：Ready for App Store Connect Submission (1.0.0)  
> **支持设备**：iPhone (iOS 16.0+)、iPad (iPadOS 16.0+)、Mac (macOS 14.0+，支持 Apple Silicon 与 Intel)  
> **设计语言**：SwiftUI 原生架构 · Apple Human Interface Guidelines 规范  

---

## 目录
1. [App 基本元数据 (Metadata)](#一app-基本元数据-metadata)
2. [App Store 宣传文案 (中简 / 中繁 / 英文)](#二app-store-宣传文案)
3. [App Store 搜索关键词 (Keywords)](#三app-store-搜索关键词-keywords)
4. [版本更新说明 (What's New in 1.0.0)](#四版本更新说明-whats-new)
5. [隐私政策规范 (Privacy Policy)](#五隐私政策规范-privacy-policy)
6. [宣传截屏与图片规格 (Screenshots & Assets)](#六宣传截屏与图片规格)
7. [App Store 审核应对指南 (Review Guidelines Checklist)](#七app-store-审核应对指南)

---

## 一、App 基本元数据 (Metadata)

| 字段名称 | 推荐填写内容 | 说明 |
| :--- | :--- | :--- |
| **App 名称 (Name)** | `PDFview - 智能PDF与图片重排阅读器` | 建议控制在 30 字符内，包含品牌与核心功能词 |
| **App 副标题 (Subtitle)** | `智能重排·竖排古籍·切边纠偏·云端同步` | 30 字符内，精准概括 4 大核心特色 |
| **Bundle ID** | `com.duokan.pdfview` (或当前开发者账号 Prefix) | 需与 Xcode Target 保持一致 |
| **SKU** | `PDFVIEW_2026_IOS` | 内部唯一标识 |
| **主类别 (Primary Category)** | **图书 (Books)** | 首选分类，目标受众集中 |
| **次类别 (Secondary Category)** | **效率 (Productivity)** 或 **工具 (Utilities)** | 辅助搜索曝光 |
| **内容版权 (Content Rights)** | 是，拥有该应用程序的全部专有权利 | 独立研发原生软件 |
| **年龄分级 (Age Rating)** | **4+** (无任何暴力、成人或限制级内容) | 纯本地阅读工具 |
| **价格与销售范围** | **免费 (Free)** / 全球 175 个国家与地区发售 | 无强制内购，零门槛获客 |
| **主语言** | 简体中文 (Simplified Chinese) | 支持中简、中繁、英、德、日 5 种本地化 |

---

## 二、App Store 宣传文案

### 1. 简体中文 (zh-Hans)

#### 宣传文本 (Promotional Text · 170 字符上限)
> 传承经典多看排版精髓！专为手机小屏优化的 PDF 与扫描图片智能重排阅读器。独家支持竖排古籍单栏流式重构、四角手动切边纠偏、四色温润护眼纸张、Apple 原生离线双语翻译与 iCloud 跨设备毫秒级同步。

#### 详细描述 (Description)
```text
PDFview 是一款专为 iPhone、iPad 与 Mac 深度打造的高品质 PDF 与长图排版阅读器。针对移动设备屏幕痛点，重现经典「多看排版」的温润阅读质感，让扫描书籍、学术论文、古代善本与相机照片在手机上重获大字流畅阅读体验。

【核心功能亮点】

◆ 智能双模式重排 · 告别手机眯眼缩放
· 高清晰图形切片重排：毫秒级自动分析版面，段落、图表与印章完整内嵌，100% 保留原书印刷风貌。
· 无损矢量文字重排：支持 50%–300% 自由字号缩放与行距自适应，享受 iOS 原生流畅长按划词与划线复制。
· 本地超长图完整重排：支持从相册导入高清超长截图与照片，智能垂直切分分段，彻底杜绝排版截断。

◆ 竖排古籍善本重构 · 传统文化阅读利器
· 专设独立「[✓] 竖排」复选框，一键直观开关，拒绝层层深叠菜单。
· 智能按列逆序解构古代善本与右起（RTL）书刊，重构成符合现代习惯的舒适流式排版。
· 左右轻扫手势自动反转翻页方向，贴合传统翻书习惯。

◆ 交互式手动切边与方框纠偏
· 针对手机拍摄倾斜、书脊弯曲、黑边过宽的书籍照片，提供高精度四角与四边拖拽选区。
· 实时应用硬件加速透视纠偏（Perspective Correction），倾斜梯形秒变平直矩形。
· 彻底切除桌面杂物与黑边，大幅提升后续排版与 OCR 识别精度。

◆ 极简全图案工具栏与严密翻页
· 顶栏紧凑图案内置：✂️ 手动切边纠偏、📋 一键复制全文、🔄 顺时针 90° 旋转、⚙️ 舒适全屏设置。
· 优化触控动力学，严格整页翻页锁定，彻底杜绝滑动停留半页的卡滞现象。

◆ 四色护眼纸张与原生离线双语翻译
· 纯白、羊皮羊绒护眼、豆沙绿意与夜间暗黑四种温润纸张主题，搭配多档舒适行距。
· 深度集成 Apple 原生离线翻译引擎，扫描件或文字版 PDF 均可一键即时双语对照。

◆ iCloud 跨设备无缝双向同步
· 自动在 iPhone、iPad 和 Mac 间双向同步图书文件，主界面云端书库支持一键刷新与按需下载。
· 毫秒级云端同步阅读进度：已读页码、排版模式、缩放比与切边参数实时跨端共享。

◆ 100% 纯本地运行 · 尊重用户隐私
· 所有排版切片、OCR 识别与图像校正均在设备端本地硬件运行，零服务器中转，零数据收集。
```

---

### 2. 繁體中文 (zh-Hant)

#### 宣傳文字 (Promotional Text)
> 傳承經典多看排版精髓！專為手機小螢幕打造的 PDF 與掃描圖書智慧重排閱讀器。獨家支援古籍直排流式重構、四角手動切邊糾偏、四色護眼紙張與 iCloud 跨裝置同步。

#### 詳細描述 (Description)
```text
PDFview 是一款專為 iPhone、iPad 與 Mac 深度打造的高品質 PDF 與長圖排版閱讀器。針對行動裝置螢幕痛點，重現經典「多看排版」的溫潤閱讀質感，讓掃描書籍、學術論文、古代善本與相機照片在手機上重獲大字流暢閱讀體驗。

【核心特色】
◆ 智慧雙模式重排：高解析圖形切片橫排 + 向量文字橫排，50%–300% 自由無損縮放。
◆ 直排古籍善本重構：頂列專設直排開關，右起古代書籍智慧逆序重構為舒適流式版面。
◆ 手動切邊與梯形糾偏：四角自由拖曳，硬體加速透視拉伸，傾斜歪斜秒變端正。
◆ 嚴密整頁切換：告別滑動停留在半頁的困擾，左右輕掃極致絲滑。
◆ 精簡圖案工具列：包含手動切邊、複製全文、順時針90°旋轉與全螢幕設定。
◆ 四色護眼紙張與離線翻譯：羊皮紙、豆沙綠、夜間黑，整合 Apple 原生離線對照翻譯。
◆ iCloud 跨裝置同步：iPhone、iPad 與 Mac 間圖書與閱讀進度即時雙向無縫互通。
◆ 隱私安全：純本機演算法執行，零伺服器上傳，100% 離線隱私保障。
```

---

### 3. 英文 (English - US / Global)

#### Promotional Text (170 characters)
> The classic reflow reader reborn for mobile! Smart PDF reflow, vertical ancient books deconstruction, manual perspective deskew, eye-care themes, and iCloud sync.

#### Description
```text
PDFview brings the authentic, warm reading typography of legendary e-readers to your iPhone, iPad, and Mac. Designed specifically to solve the frustration of reading dense PDFs and scanned documents on small mobile screens.

KEY FEATURES:

◆ Smart Dual-Mode Reflow
· High-Fidelity Graphic Slices: Intelligently segments paragraphs, inline tables, and illustrations while preserving 100% of the original publication layout.
· Lossless Vector Text Reflow: Enjoy crisp 50%–300% font scaling and native iOS text selection.
· Panoramic Long Image Support: Import long screenshots and mobile captures from Photos with seamless vertical segmenting.

◆ Classical Vertical Book Deconstruction
· Dedicated '[✓] Vertical' toggle on the toolbar—no confusing nested menus.
· Reconstructs traditional right-to-left (RTL) vertical columns into a comfortable single-column mobile reading flow.
· Natural touch-swipe gestures adapt automatically to historical book reading habits.

◆ Quadrilateral Crop & Perspective De-skew
· Interactive 4-corner dragging engineered for tilted camera captures and curved book spines.
· Hardware-accelerated CIPerspectiveCorrection unwarps trapezoids into crisp, flat rectangles.
· Eliminates black scan borders and background clutter for pristine OCR and reflow accuracy.

◆ Strict Full-Page Swiping & Compact Toolbar
· Kinetic-locked full-page swiping guarantees clean transitions without awkward half-page stops.
· Compact icon toolbar: ✂️ Crop & Deskew, 📋 Copy Text, 🔄 90° Clockwise Rotation, ⚙️ Fullscreen Settings.

◆ Eye-Care Themes & Offline Bilingual Translation
· 4 calming paper palettes: Pure White, Sepia Cashmere, Soft Green, and Dark Mode.
· Integrated Apple offline translation for instant side-by-side bilingual reading across dozens of languages.

◆ Seamless iCloud Multi-Device Synchronization
· Automatically syncs imported books across iPhone, iPad, and Mac via iCloud Drive.
· Millisecond reading progress, page bookmarks, and custom crop quad synchronization.

◆ 100% Offline & Private
· All processing, reflow, and OCR algorithms run strictly on-device. Zero data collection, zero tracking.
```

---

## 三、App Store 搜索关键词 (Keywords)

> **注**：App Store 限制关键词在 100 字节以内，逗号分隔，无空格。

### 中文版关键词 (100 字符内优化组合)
```text
PDF重排,多看阅读,古籍善本,竖排转换,扫描切边,透视校正,长图阅读,PDF阅读器,双语翻译,iCloud同步,大字排版,论文阅读
```

### 英文版关键词 (English Keywords · Under 100 bytes)
```text
PDF reflow,eReader,book scanner,deskew,crop,vertical text,OCR,bilingual reader,iCloud sync,viewer
```

---

## 四、版本更新说明 (What's New)

**版本号**：`1.0.0`
```text
【PDFview 1.0.0 正式首发】
· 经典多看排版引擎：支持图形切片与矢量文字双模式重排，小屏大字畅读 PDF。
· 竖排古籍重构：专设竖排直览开关，智能逆序解构右起古书。
· 四角手动切边纠偏：四点透视校正，拍摄倾斜与弯曲梯形秒变平直。
· 顺时针 90° 旋转与整页锁定：优化滑动手势，杜绝滑停半页；支持单页与全书旋转。
· iCloud 云端书库：iPhone、iPad 与 Mac 多端图书与阅读进度实时无缝同步。
· 四色护眼纸张与 Apple 原生离线双语翻译。
```

---

## 五、隐私政策规范 (Privacy Policy)

> 苹果 App Store 审核准则（Guideline 5.1）强制要求提供隐私政策 URL。PDFview 属于 **零数据收集（No Data Collected）** 应用程序。

### 隐私政策正文 (可直接部署至 GitHub Pages 或个人官网)

```markdown
# Privacy Policy for PDFview

Last updated: October 16, 2026

PDFview ("the App") is developed as a privacy-first, on-device document reader. We believe that your documents and reading habits belong solely to you.

### 1. Zero Data Collection
PDFview does NOT collect, transmit, store, or sell any personal data, analytics, device identifiers, or usage logs. We have no external tracking SDKs, no advertisement frameworks, and no remote analytics services.

### 2. Document & Image Processing
All PDF rendering, layout reflow, text extraction, OCR recognition, and perspective crop corrections are processed strictly on your local device hardware (Apple Silicon / CPU / GPU). Your books and photos never leave your device.

### 3. iCloud Synchronization
If you choose to enable iCloud sync, your documents, reading progress, and preferences are synchronized exclusively through Apple's official, encrypted iCloud Drive and NSUbiquitousKeyValueStore under your own Apple ID. The developer has no access to your iCloud data or storage.

### 4. Third-Party Services
PDFview contains zero third-party trackers, zero third-party advertising SDKs, and zero social media SDKs. Offline translation uses Apple's native system translation frameworks.

### 5. Contact & Support
If you have questions about this Privacy Policy, please contact:
Email: support@pdfview.app (or your developer contact email)
```

---

## 六、宣传截屏与图片规格

项目已内置自动化截屏生成脚本：[`scripts/generate_appstore_screenshots.py`](file:///Users/mac/Downloads/pdfView/scripts/generate_appstore_screenshots.py)。

运行命令：
```bash
python3 scripts/generate_appstore_screenshots.py
```

生成图片保存在：`AppStoreAssets/Screenshots/`，已完全适配苹果要求的尺寸：

| 规格类型 | 屏幕尺寸 | 分辨率 (像素) | 对应主流机型 |
| :--- | :--- | :--- | :--- |
| **iPhone 6.9"** | 6.9 英寸 | `1320 x 2868` | iPhone 16 Pro Max |
| **iPhone 6.7"** | 6.7 英寸 | `1290 x 2796` | iPhone 15 Pro Max, 14 Pro Max |
| **iPhone 6.5"** | 6.5 英寸 | `1242 x 2688` | iPhone 11 Pro Max, XS Max |
| **iPhone 5.5"** | 5.5 英寸 | `1242 x 2208` | iPhone 8 Plus, iPhone SE (2/3 代) |
| **iPad 13.0"** | 13.0 英寸 | `2064 x 2752` | iPad Pro 13 英寸 (M4 / 第 6 代) |

### 5 张宣传图设计主题规划：
1. **01_smart_reflow**：大字畅读 PDF · 重现经典多看排版（展示双模式重排对比与本地长图支持）。
2. **02_crop_deskew**：告别倾斜畸变 · 梯形秒变平直（展示四角可拖拽透视纠偏与黑边切除）。
3. **03_vertical_ancient**：古籍竖排流式化 · 智能逆序重构（展示古籍一键直排与手势自适应）。
4. **04_themes_translate**：四色温润纸张 · 离线双语对照（展示羊皮纸色板与 Apple 离线即时翻译）。
5. **05_icloud_sync**：跨设备无缝接力 · 进度实时共享（展示 iPhone / iPad / Mac 多端云书库互通）。

---

## 七、App Store 审核应对指南

针对 Apple Reviewer 常见的审核关注点与应对策略：

1. **Guideline 2.1 - App Completeness (功能完整性)**：
   - 确保应用无空链接、无测试占位符（Lorem Ipsum）。
   - 主界面已精简，操作指南点击后全屏完整展示，iCloud 刷新动效正常，无崩溃风险。
2. **Guideline 2.3 - Accurate Metadata (元数据准确性)**：
   - 截屏展示的所有功能在应用内均真实可用（如切边纠偏、竖排重排、iCloud 同步）。
3. **Guideline 5.1.1 - Data Collection and Storage (数据与权限)**：
   - App Store Connect 的「App 隐私」问卷中，直接勾选 **“否，我们不从此 App 中收集数据”**。这一项极受苹果审核团队青睐，通常会加速审核通过。
4. **iCloud Entitlement 审核备注 (Reviewer Notes)**：
   - 审核备注写明：“This app uses iCloud Drive and NSUbiquitousKeyValueStore exclusively to sync user-imported documents and reading progress between the user's own Apple devices. No external server is involved.”
