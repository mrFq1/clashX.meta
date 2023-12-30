//
//  MetaTask.swift
//  com.metacubex.ClashX.ProxyConfigHelper


import Cocoa

class MetaTask: NSObject {
	
	struct MetaServer: Encodable {
        var externalController: String
		let secret: String
		var log: String = ""
		
		func jsonString() -> String {
			let encoder = JSONEncoder()
			encoder.outputFormatting = .prettyPrinted
			
			guard let data = try? encoder.encode(self),
				  let string = String(data: data, encoding: .utf8) else {
				return ""
			}
			return string
		}
	}
	
	struct MetaCurl: Decodable {
		let hello: String
	}
	
	let proc = Process()
	let procQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".MetaProcess")
	
	var timer: DispatchSourceTimer?
	let timerQueue = DispatchQueue(label: Bundle.main.bundleIdentifier! + ".timer")
	
	@objc func setLaunchPath(_ path: String) {
		proc.executableURL = .init(fileURLWithPath: path)
	}
	
	var logStopped = false
	
	@objc func start(_ confPath: String,
					 confFilePath: String,
					 result: @escaping stringReplyBlock) {
		
		initLog(confPath)
		log("========================================")
		var resultReturned = false
		
		func returnResult(_ re: String) {
			guard !resultReturned else { return }
			timer?.cancel()
			timer = nil
			resultReturned = true
			logStopped = true
			result(re)
		}
		
		var args = [
			"-d",
			confPath
		]
		
		if confFilePath != "" {
			args.append(contentsOf: [
				"-f",
				confFilePath
			])
		}
		
		killOldProc()
		log("killOldProc finish")
		do {
			if let info = self.test(confPath, confFilePath: confFilePath) {
				log("Test meta config failed.")
				returnResult(info)
				return
			} else {
				log("Test meta config success.")
				print("Test meta config success.")
			}
			
			guard var serverResult = self.parseConfFile(confPath, confFilePath: confFilePath) else {
				
				log("Can't decode config file.")
				returnResult("Can't decode config file.")
				return
			}
			
			
			log("set pipe")
			self.proc.arguments = args
			self.proc.qualityOfService = .userInitiated
			
			let pipe = Pipe()
			var logs = [String]()
			
			let errorPipe = Pipe()
			var errorLogs = [String]()
			
			pipe.fileHandleForReading.readabilityHandler = { pipe in
				guard let output = String(data: pipe.availableData, encoding: .utf8),
					  !resultReturned else {
					self.log("pipe ignore")
					return
				}
				
				output.split(separator: "\n").map {
					self.formatMsg(String($0))
				}.forEach {
					logs.append($0)
					if $0.contains("External controller listen error:") || $0.contains("External controller serve error:") {
						self.log("External controller serve error:")
						returnResult($0)
					}
					
					/*
					 if let range = $0.range(of: "RESTful API listening at: ") {
					 let addr = String($0[range.upperBound..<$0.endIndex])
					 guard addr.split(separator: ":").count == 2,
					 let port = Int(addr.split(separator: ":")[1]) else {
					 returnResult("Not found RESTful API port.")
					 return
					 }
					 let testLP = self.testListenPort(port)
					 if testLP.pid != 0,
					 testLP.pid == self.proc.processIdentifier,
					 testLP.addr == addr {
					 serverResult.log = logs.joined(separator: "\n")
					 returnResult(serverResult.jsonString())
					 } else {
					 returnResult("Check RESTful API pid failed.")
					 }
					 }
					 */
					
					if $0.contains("RESTful API listening at:") {
						if self.testExternalController(serverResult) {
							serverResult.log = logs.joined(separator: "\n")
							self.log("RESTful API listening at:")
							returnResult(serverResult.jsonString())
						} else {
							self.log("Check RESTful API failed.")
							returnResult("Check RESTful API failed.")
						}
					}
					
					self.log("pipe ignore2")
				}
			}
			
			
			errorPipe.fileHandleForReading.readabilityHandler = { pipe in
				guard let output = String(data: pipe.availableData, encoding: .utf8) else {
					self.log("errorPipe1")
					return
				}
				output.split(separator: "\n").forEach {
					errorLogs.append(String($0))
				}
				
				self.log("errorPipe2")
			}
			
			
			self.proc.standardError = errorPipe
			self.proc.standardOutput = pipe
			
			self.proc.terminationHandler = { proc in
				self.log("terminationHandler")
				guard !resultReturned else {
					guard errorLogs.count > 0 else {
						self.log("errorLogs.count 0")
						return
					}
					
					errorLogs.append("terminationStatus: \(proc.terminationStatus)")
					errorLogs.append("terminationReason: \(proc.terminationReason)")
					
					let data = errorLogs.joined(separator: "\n").data(using: .utf8)
					
					let url = URL(fileURLWithPath: confPath)
						.appendingPathComponent("logs")
					
					let fm = FileManager.default
					try? fm.createDirectory(atPath: url.path, withIntermediateDirectories: true)
					
					let fileName = {
						let dateformat = DateFormatter()
						dateformat.dateFormat = "yyyy-MM-dd_HH-mm-ss"
						let s = dateformat.string(from: Date())
						return "meta_core_crash_\(s).log"
					}()
					
					fm.createFile(atPath: url.appendingPathComponent(fileName).path, contents: data)
					
					self.log("crash file")
					return
				}
				
				
				let data = pipe.fileHandleForReading.readDataToEndOfFile()
				guard let string = String(data: data, encoding: String.Encoding.utf8) else {
					self.log("Meta process terminated, no found output.")
					returnResult("Meta process terminated, no found output.")
					return
				}
				
				let results = string.split(separator: "\n").map(String.init).map(self.formatMsg(_:))
				
				self.log("terminated returnResult")
				
				returnResult(results.joined(separator: "\n"))
			}
			
			log("set timer")
			
			self.timer = DispatchSource.makeTimerSource(queue: self.timerQueue)
			self.timer?.schedule(deadline: .now(), repeating: .milliseconds(500))
			self.timer?.setEventHandler {
				guard self.testExternalController(serverResult) else {
					self.log("testExternalController  ignore")
					
					return
				}
				serverResult.log = logs.joined(separator: "\n")
				self.log("testExternalController success")
				returnResult(serverResult.jsonString())
			}
			
			DispatchQueue.global().asyncAfter(deadline: .now() + 30) {
				serverResult.log = logs.joined(separator: "\n")
				self.log("30s timeout")
				returnResult(serverResult.jsonString())
			}
			
			self.log("proc.run()")
			try self.proc.run()
			self.timer?.resume()
		} catch let error {
			self.log("Start meta error")
			returnResult("Start meta error, \(error.localizedDescription).")
		}
	}
	
	@objc func stop() {
		log(#function)
		DispatchQueue.main.async {
			guard self.proc.isRunning else { return }
			let proc = Process()
			proc.executableURL = .init(fileURLWithPath: "/bin/kill")
			proc.arguments = ["-9", "\(self.proc.processIdentifier)"]
			try? proc.run()
			proc.waitUntilExit()
		}
	}
	
	@objc func test(_ confPath: String, confFilePath: String) -> String? {
		log(#function)
		do {
			let proc = Process()
			proc.executableURL = self.proc.executableURL
			var args = [
				"-t",
				"-d",
				confPath
			]
			if confFilePath != "" {
				args.append(contentsOf: [
					"-f",
					confFilePath
				])
			}
			let pipe = Pipe()
			proc.standardOutput = pipe
			
			proc.arguments = args
			try proc.run()
			proc.waitUntilExit()
			
			guard proc.terminationStatus == 0 else {
				return "Test failed, status \(proc.terminationStatus)"
			}
			
			let data = pipe.fileHandleForReading.readDataToEndOfFile()
			guard let string = String(data: data, encoding: String.Encoding.utf8) else {
				return "Test failed, no found output."
			}
			
			let results = string.split(separator: "\n").map(String.init).map(formatMsg(_:))
			
			guard let re = results.last else {
				return "Test failed, no found output."
			}
			
			if re.hasPrefix("configuration file"),
			   re.hasSuffix("test is successful") {
				return nil
			} else if re.hasPrefix("configuration file"),
					  re.hasSuffix("test failed") {
				return results.count > 1
				? results[results.count - 2]
				: "Test failed, unknown result."
			} else {
				return re
			}
		} catch let error {
			return "\(error)"
		}
	}
	
	func killOldProc() {
		let proc = Process()
		proc.executableURL = .init(fileURLWithPath: "/usr/bin/killall")
		proc.arguments = ["com.metacubex.ClashX.ProxyConfigHelper.meta"]
		try? proc.run()
		proc.waitUntilExit()
	}
	
	@objc func getUsedPorts(_ result: @escaping stringReplyBlock) {
		log(#function)
		let proc = Process()
		let pipe = Pipe()
		proc.standardOutput = pipe
		proc.executableURL = .init(fileURLWithPath: "/bin/bash")
		proc.arguments = ["-c", "lsof -nP -iTCP -sTCP:LISTEN | grep LISTEN"]
		try? proc.run()
		proc.waitUntilExit()
		
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		guard let str = String(data: data, encoding: .utf8) else {
			result("")
			return
		}
		
		let usedPorts = str.split(separator: "\n").compactMap { str -> Int? in
			let line = str.split(separator: " ").map(String.init)
			guard line.count == 10,
				  let port = line[8].components(separatedBy: ":").last else { return nil }
			return Int(port)
		}.map(String.init).joined(separator: ",")
		
		result(usedPorts)
	}
	
	var logPath: String?
	
	func initLog(_ confPath: String) {
		guard logPath == nil else { return }
		
		let url = URL(fileURLWithPath: confPath)
			.appendingPathComponent("logs")
		
		let fm = FileManager.default
		try? fm.createDirectory(atPath: url.path, withIntermediateDirectories: true)
		
		let fileName = {
			let dateformat = DateFormatter()
			dateformat.dateFormat = "yyyy-MM-dd_HH-mm-ss"
			let s = dateformat.string(from: Date())
			return "meta_core_test_\(s).log"
		}()
		
		let path = url.appendingPathComponent(fileName).path
		fm.createFile(atPath: path, contents: nil)
		
		logPath = path
	}
	
	
	func log(_ str: String, function: String = #function, line: Int = #line) {
		guard !logStopped, let path = logPath else { return }
		
		let url = URL(fileURLWithPath: path)
		
		if let handle = try? FileHandle(forWritingTo: url) {
			var str = "\(function) [#\(line)] " + str + "\n"
			handle.seekToEndOfFile()
			handle.write(str.data(using: .utf8)!)
			handle.closeFile()
		}
	}
	
	func testListenPort(_ port: Int) -> (pid: Int32, addr: String) {
		log(#function)
		let proc = Process()
		let pipe = Pipe()
		proc.standardOutput = pipe
		proc.executableURL = .init(fileURLWithPath: "/bin/bash")
		proc.arguments = ["-c", "lsof -nP -iTCP:\(port) -sTCP:LISTEN | grep LISTEN"]
		try? proc.run()
		proc.waitUntilExit()
		
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		guard let str = String(data: data, encoding: .utf8),
			  str.split(separator: " ").map(String.init).count == 10 else {
			return (0, "")
		}
		
		let re = str.split(separator: " ").map(String.init)
		let pid = re[1]
		let addr = re[8]
		
		return (Int32(pid) ?? 0, addr)
	}
	
	func testExternalController(_ server: MetaServer) -> Bool {
		log(#function)
		let proc = Process()
		let pipe = Pipe()
		proc.standardOutput = pipe
		proc.executableURL = .init(fileURLWithPath: "/usr/bin/curl")
		var args = [server.externalController]
		if server.secret != "" {
			args.append(contentsOf: [
				"--header",
				"Authorization: Bearer \(server.secret)"
			])
		}
		
		proc.arguments = args
		try? proc.run()
		proc.waitUntilExit()
		
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		
		guard let str = try? JSONDecoder().decode(MetaCurl.self, from: data),
			  (str.hello == "clash.meta" || str.hello == "mihomo") else {
			return false
		}
		return true
	}
	
	func formatMsg(_ msg: String) -> String {
		let msgs = msg.split(separator: " ", maxSplits: 2).map(String.init)
		
		guard msgs.count == 3,
			  msgs[1].starts(with: "level"),
			  msgs[2].starts(with: "msg") else {
			return msg
		}
		
		let level = msgs[1].replacingOccurrences(of: "level=", with: "")
		var re = msgs[2].replacingOccurrences(of: "msg=\"", with: "")
		
		while re.last == "\"" || re.last == "\n" {
			re.removeLast()
		}
		
		if re.contains("time=") {
			print(re)
		}
		
		return "[\(level)] \(re)"
	}
	
	func parseConfFile(_ confPath: String, confFilePath: String) -> MetaServer? {
		log(#function)
		let fileURL = confFilePath == "" ? URL(fileURLWithPath: confPath).appendingPathComponent("config.yaml", isDirectory: false) : URL(fileURLWithPath: confFilePath)
		
		guard let data = FileManager.default.contents(atPath: fileURL.path),
			  let content = String(data: data, encoding: .utf8) else {
			return nil
		}
		let lines = content.split(separator: "\n").map(String.init)
		
		func find(_ key: String) -> String {
			var re = lines.first(where: { $0.starts(with: "\(key): ") })?.dropFirst("\(key): ".count) ?? ""
			
			if re.hasPrefix("\"") && re.hasSuffix("\"")
				|| re.hasPrefix("'") && re.hasSuffix("'") {
				re.removeLast()
				re.removeFirst()
			}
			return String(re)
		}
		
		return MetaServer(externalController: find("external-controller"),
						  secret: find("secret"))
	}
}
