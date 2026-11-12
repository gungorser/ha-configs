# Run by blender-mcp-start inside Blender (blender --python): enables the "MCP for Blender" add-on
# and starts its socket server on all interfaces, port 9876. The nftables table blender_mcp lets
# only the Proxmox host (192.168.0.220) reach it. Managed by ha-configs docker-host.
import addon_utils
import bpy

addon_utils.enable("blender_mcp", default_set=True, persistent=True)
import blender_mcp  # noqa: E402  (the add-on module, importable once enabled)

server = blender_mcp.BlenderMCPServer(host="0.0.0.0", port=9876)
bpy.types.blendermcp_server = server  # the add-on's auto-start then sees it running
server.start()
bpy.context.scene.blendermcp_server_running = True
print("BlenderMCP: listening on 0.0.0.0:9876")
