# NanoMD 延伸

> [!NOTE]<br>
> 用 NanoMD 的經驗編寫一個原生 Swift 的 Markdown Parser

## 使用方式

```Swift
import MarkdownKit

struct ContentView: View {
    let vw = UIScreen.main.bounds.size.width
    var body: some View {
        MDText(
            "**MarkdownKit**\nSwift 原生 Parser", 
            maxWidth: vw - 32
        )
    }
}
```

## 版本

- `0.1.0`
    - 保留原始 NSAttributedString Markdown 支持。
    - 添加 \#1 - \#6 擴展。
    - 添加 \!\[AlternativeText\]\(ImageLink\) 擴展。