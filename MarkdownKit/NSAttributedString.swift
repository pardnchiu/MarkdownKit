//
//  MarkdownKit.swift
//  MarkdownKit
//
//  Created by Pardn on 2025/1/14.
//

import UIKit
import SwiftUI

extension NSAttributedString {

	static func fromMarkdown(
		_ markdown: String,
		maxWidth: CGFloat,
		imageHandler: @escaping (String, CGFloat, @escaping (NSTextAttachment?) -> Void) -> Void,
		completion: @escaping (NSAttributedString) -> Void
	) {
		let mutableAttributedString = NSMutableAttributedString()

		let imagePattern = #"!\[\]\((.*?)\)"#
		let regex = try! NSRegularExpression(pattern: imagePattern, options: [])
		let matches = regex.matches(in: markdown, range: NSRange(location: 0, length: markdown.utf16.count))

		var lastRangeEnd = 0
		var imagePositions: [(position: Int, url: String)] = []
		let group = DispatchGroup()

		func applyHeaderStyle(_ text: String) -> NSAttributedString {
			let lines = text.split(separator: "\n", omittingEmptySubsequences: true)
			let result = NSMutableAttributedString()

			for line in lines {
				if let match = line.range(of: #"^(#{1,6}) (.*)"#, options: .regularExpression) {
					let hashes = line[match].prefix { $0 == "#" }.count
					let content = line[match].dropFirst(hashes + 1)

					let attributes: [NSAttributedString.Key: Any]
					switch hashes {
						case 1:
							attributes = [.font: UIFont.boldSystemFont(ofSize: 28)]
						case 2:
							attributes = [.font: UIFont.boldSystemFont(ofSize: 24)]
						case 3:
							attributes = [.font: UIFont.boldSystemFont(ofSize: 20)]
						case 4:
							attributes = [.font: UIFont.boldSystemFont(ofSize: 18)]
						case 5:
							attributes = [.font: UIFont.boldSystemFont(ofSize: 16)]
						default:
							attributes = [.font: UIFont.boldSystemFont(ofSize: 14)]
					}

					result.append(NSAttributedString(string: "\(content)\n", attributes: attributes))
				} else {
					// 默認文字大小為 14
					let defaultAttributes: [NSAttributedString.Key: Any] = [
						.font: UIFont.systemFont(ofSize: 14)
					]
					result.append(NSAttributedString(string: "\(line)\n", attributes: defaultAttributes))
				}
			}

			return result
		}

		// 首先處理所有文本，並記錄圖片位置
		if (matches.count > 0) {
			for match in matches {
				let range = match.range
				let urlRange = match.range(at: 1)

				// 處理圖片前的文本
				if range.location > lastRangeEnd {
					let precedingTextRange = NSRange(location: lastRangeEnd, length: range.location - lastRangeEnd)
					let precedingText = (markdown as NSString).substring(with: precedingTextRange)
					let attributedText = applyHeaderStyle(precedingText)
					mutableAttributedString.append(attributedText)
				}

				// 記錄圖片位置和URL
				let insertPosition = mutableAttributedString.length
				let url = (markdown as NSString).substring(with: urlRange)
				imagePositions.append((insertPosition, url))

				// 先插入一個占位符
				mutableAttributedString.append(NSAttributedString(string: "[IMAGE]"))

				lastRangeEnd = range.location + range.length
			}
		}
		else {
			// 處理圖片前的文本
			if lastRangeEnd < markdown.utf16.count {
				let precedingTextRange = NSRange(location: lastRangeEnd, length: markdown.utf16.count - lastRangeEnd)
				let precedingText = (markdown as NSString).substring(with: precedingTextRange)
				let attributedText = applyHeaderStyle(precedingText)
				mutableAttributedString.append(attributedText)
			}
		}

		// 處理最後剩餘的文本
		if lastRangeEnd < markdown.utf16.count {
			let remainingTextRange = NSRange(location: lastRangeEnd, length: markdown.utf16.count - lastRangeEnd)
			let remainingText = (markdown as NSString).substring(with: remainingTextRange)
			if let remainingAttributedText = try? NSAttributedString(markdown: remainingText) {
				let mutableRemainingText = NSMutableAttributedString(attributedString: remainingAttributedText)

				// 遍歷整段文字並應用默認字體大小為 14
				let range = NSRange(location: 0, length: mutableRemainingText.length)
				mutableRemainingText.enumerateAttributes(in: range, options: []) { attributes, range, _ in
					var newAttributes = attributes
					// 如果當前沒有設置字體，或者設置了其他字體，統一替換為大小 14 的系統字體
					if newAttributes[.font] == nil || !(newAttributes[.font] is UIFont) {
						newAttributes[.font] = UIFont.systemFont(ofSize: 14)
					}
					mutableRemainingText.setAttributes(newAttributes, range: range)
				}

				mutableAttributedString.append(mutableRemainingText)
			}
		}

		// 從後往前加載和替換圖片
		var loadedImages: [Int: NSTextAttachment] = [:]

		for (index, imageInfo) in imagePositions.enumerated() {
			group.enter()
			imageHandler(imageInfo.url, maxWidth) { attachment in
				if let attachment = attachment {
					loadedImages[index] = attachment
				}
				group.leave()
			}
		}

		// 當所有圖片都加載完成後，從後往前替換
		group.notify(queue: .main) {
			// 反轉順序處理
			for (index, imageInfo) in imagePositions.enumerated().reversed() {
				let range = NSRange(location: imageInfo.position, length: "[IMAGE]".count)
				if let attachment = loadedImages[index] {
					let imageString = NSMutableAttributedString()
					imageString.append(NSAttributedString(attachment: attachment))
					imageString.append(NSAttributedString(string: "\n"))
					mutableAttributedString.replaceCharacters(in: range, with: imageString)
				} else {
					let placeholder = NSAttributedString(string: "[Image not available]\n")
					mutableAttributedString.replaceCharacters(in: range, with: placeholder)
				}
			}

			completion(mutableAttributedString)
		}
	}
}

// 非同步加載圖片
func loadImage(from urlString: String, maxWidth: CGFloat, completion: @escaping (NSTextAttachment?) -> Void) {
	guard let url = URL(string: urlString) else {
		completion(nil)
		return
	}

	URLSession.shared.dataTask(with: url) { data, response, error in
		guard let data = data, let image = UIImage(data: data) else {
			DispatchQueue.main.async {
				completion(nil)
			}
			return
		}

		let attachment = NSTextAttachment()
		attachment.image = image

		// 計算縮放比例，假設我們希望最大寬度為 300 點
		//		let maxWidth: CGFloat = 300
		let aspectRatio = image.size.width / image.size.height

		if image.size.width > maxWidth {
			// 如果圖片寬度大於最大寬度，按比例縮放
			let newWidth = maxWidth
			let newHeight = newWidth / aspectRatio
			attachment.bounds = CGRect(x: 0, y: -5, width: newWidth, height: newHeight)
		} else {
			// 如果圖片寬度小於最大寬度，使用原始大小
			attachment.bounds = CGRect(x: 0, y: -5, width: image.size.width, height: image.size.height)
		}

		DispatchQueue.main.async {
			completion(attachment)
		}
	}.resume()
}
