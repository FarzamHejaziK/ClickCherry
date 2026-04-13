import Foundation

enum MCPTestServerFixture {
    static func makeServerScript() throws -> URL {
        let tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)

        let scriptURL = tempDirectory.appendingPathComponent("fake_mcp_server.py", isDirectory: false)
        let script = """
        import json
        import sys

        def read_message():
            headers = b""
            while b"\\r\\n\\r\\n" not in headers:
                chunk = sys.stdin.buffer.read(1)
                if not chunk:
                    return None
                headers += chunk
            header_text, _ = headers.split(b"\\r\\n\\r\\n", 1)
            content_length = None
            for line in header_text.decode("utf-8").split("\\r\\n"):
                if line.lower().startswith("content-length:"):
                    content_length = int(line.split(":", 1)[1].strip())
                    break
            if content_length is None:
                raise RuntimeError("Missing Content-Length")
            body = sys.stdin.buffer.read(content_length)
            return json.loads(body.decode("utf-8"))

        def write_message(payload):
            body = json.dumps(payload).encode("utf-8")
            header = f"Content-Length: {len(body)}\\r\\n\\r\\n".encode("utf-8")
            sys.stdout.buffer.write(header + body)
            sys.stdout.buffer.flush()

        while True:
            message = read_message()
            if message is None:
                break
            method = message.get("method")
            request_id = message.get("id")
            if method == "initialize":
                write_message({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "protocolVersion": "2025-03-26",
                        "capabilities": {"tools": {}},
                        "serverInfo": {"name": "Fake MCP Server", "version": "1.0"}
                    }
                })
            elif method == "notifications/initialized":
                continue
            elif method == "tools/list":
                write_message({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "tools": [
                            {
                                "name": "browser_snapshot",
                                "description": "Return a fake browser snapshot.",
                                "inputSchema": {
                                    "type": "object",
                                    "properties": {
                                        "kind": {"type": "string"}
                                    },
                                    "additionalProperties": True
                                }
                            }
                        ]
                    }
                })
            elif method == "tools/call":
                write_message({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "result": {
                        "content": [
                            {"type": "text", "text": "fake snapshot"}
                        ],
                        "isError": False
                    }
                })
            else:
                write_message({
                    "jsonrpc": "2.0",
                    "id": request_id,
                    "error": {
                        "code": -32601,
                        "message": f"Unknown method: {method}"
                    }
                })
        """
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)
        return scriptURL
    }
}
