# /// script
# requires-python = ">=3.10"
# dependencies = ["mcp>=1.12,<2"]
# ///
from mcp.server.fastmcp import FastMCP
import pet

server=FastMCP("Jiumi")


@server.tool()
def list_pets() -> list:
    """List pets belonging to the connected user."""
    return [{k:p[k] for k in ("id","name","revision","plugins")} for p in pet.api("pets")]


@server.tool()
def save_pet(pet_id:str) -> dict:
    """Save a local pet to the user's account with revision checking."""
    return pet.save(pet_id)


@server.tool()
def restore_pet(pet_id:str) -> dict:
    """Restore a pet and its enabled extension definitions to this device."""
    return pet.restore(pet_id)


@server.tool()
def list_extensions() -> list:
    """List interaction extensions hosted by the platform."""
    return pet.api("plugins")


if __name__=="__main__":
    server.run()
