import pytest
from fastapi.testclient import TestClient
from unittest.mock import MagicMock, patch
from main import app

client = TestClient(app)

def test_health_check():
    """Test if the health endpoint works"""
    response = client.get("/health")
    assert response.status_code == 200
    assert response.json()["status"] == "healthy"

@patch("main.store") # Mock Feast Feature Store
@patch("main.model") # Mock MLflow Model
def test_predict_success(mock_model, mock_store):
    """Test a successful prediction with mocked dependencies"""
    
    mock_store.get_online_features.return_value.to_dict.return_value = {
        "TransactionID": [2987000],
        "TransactionAmt": [50.0],
        "card1": [1000],
        "card2": [500],
        "addr1": [300]
    }
    
    mock_model.predict.return_value = [0] # Not Fraud
    mock_model.predict_proba.return_value = [[0.95, 0.05]] # 5% Fraud probability
    
    response = client.get("/predict/2987000")
    
    assert response.status_code == 200
    data = response.json()
    assert data["transaction_id"] == 2987000
    assert data["is_fraud"] is False
    assert "fraud_probability" in data