import sys
import os
import pytest
from fastapi.testclient import TestClient
import json
from unittest.mock import patch, MagicMock

# Add parent directory to path
sys.path.append(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))

from main import app, embed_text

# Create test client
client = TestClient(app)

# Sample test data
SAMPLE_VECTOR = [0.01] * 768
SAMPLE_PAGE_CONTENT = """
    Shamrock Stillman nurses a glass of scotch, watching the spiral pattern in the sky.
    The tower looms in the distance, its ancient stones reflecting the moonlight.
    He knows the secrets it contains, but fears what might happen if he speaks them aloud.
    The Entrance Way had always been more than a place - it was a threshold between worlds.
"""

# Mock the embedding function
@pytest.fixture
def mock_embed():
    with patch("main.embed_text", return_value=SAMPLE_VECTOR):
        yield

# Mock the search function
@pytest.fixture
def mock_search():
    with patch("main.search", return_value=["42"]):
        yield

# Mock the httpx client for Stargate API
@pytest.fixture
def mock_httpx_get():
    with patch("httpx.AsyncClient.get") as mock_get:
        # Create a mock response
        mock_response = MagicMock()
        mock_response.status_code = 200
        mock_response.json.return_value = {"content": SAMPLE_PAGE_CONTENT}
        mock_get.return_value = mock_response
        yield mock_get

def test_health_check():
    """Test the health check endpoint."""
    response = client.get("/health")
    assert response.status_code == 200
    assert "status" in response.json()
    assert response.json()["status"] == "healthy"

@pytest.mark.asyncio
async def test_embed_text_error():
    """Test error handling in embed_text function."""
    with patch("httpx.AsyncClient.post") as mock_post:
        # Simulate an error
        mock_post.side_effect = Exception("Test error")
        
        # Check that the function raises an error
        with pytest.raises(Exception):
            await embed_text("test text")

def test_retrieve_endpoint(mock_embed, mock_search, mock_httpx_get):
    """Test the retrieve endpoint returns properly formatted quotes."""
    response = client.get("/retrieve?q=Shamrock")
    
    # Check response
    assert response.status_code == 200
    assert isinstance(response.json(), list)
    assert len(response.json()) > 0
    
    # Check the first result
    result = response.json()[0]
    assert "page_id" in result
    assert "quote" in result
    assert result["page_id"] == "42"
    
    # Verify quote is not too long
    assert len(result["quote"].split()) <= 40
    
    # Verify the quote contains something from the page content
    assert any(word in result["quote"] for word in ["Shamrock", "spiral", "tower"])

def test_refresh_endpoint():
    """Test the refresh endpoint."""
    # Test data
    test_data = {
        "page_id": "test-page",
        "vector": [0.1] * 768
    }
    
    # Send request
    response = client.post("/refresh", json=test_data)
    
    # Check response
    assert response.status_code == 202
    assert response.json() == {"status": "ok"}

if __name__ == "__main__":
    pytest.main(["-xvs", __file__])