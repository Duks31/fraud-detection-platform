import streamlit as st
import requests
import time

st.set_page_config(page_title="Sentinel Fraud Monitor", page_icon="🛡️", layout="centered")

st.markdown("""
    <style>
    .main {
        background-color: #f5f7f9;
    }
    [data-testid="stMetricValue"] {
        color: #1f2937 !important;
        font-weight: bold;
    }
    [data-testid="stMetricLabel"] {
        color: #4b5563 !important;
    }
    .stMetric {
        background-color: #ffffff;
        padding: 15px;
        border-radius: 10px;
        box-shadow: 0 2px 4px rgba(0,0,0,0.05);
        border: 1px solid #e5e7eb;
    }
    </style>
    """, unsafe_allow_html=True)

st.title("🛡️ Sentinel: Fraud Detection Hub")
st.markdown("##### Real-Time Transaction Intelligence & Monitoring")

st.sidebar.header("Manual Review")
transaction_id = st.sidebar.number_input("Enter Transaction ID", value=2987000, step=1)
analyze_btn = st.sidebar.button("Analyze Transaction", use_container_width=True)

if analyze_btn:
    with st.spinner('📡 Querying Feature Store & Running Inference...'):
        try:
            response = requests.get(f"http://serving_api:8000/predict/{transaction_id}")
            
            time.sleep(0.7) 
            
            if response.status_code == 200:
                data = response.json()
                
                st.subheader(f"Results for ID: #{transaction_id}")
                
                col1, col2 = st.columns(2)
                prob = data['fraud_probability']
                
                with col1:
                    st.metric(label="Fraud Probability", value=f"{prob * 100:.2f}%")
                
                with col2:
                    if data['is_fraud']:
                        st.error("🚨 ALERT: FRAUDULENT")
                    else:
                        st.success("✅ STATUS: SECURE")
                
                st.progress(prob)
                
                with st.expander("View Raw Metadata"):
                    st.write(data)
                    
            else:
                st.error(f"❌ API Error: {response.json().get('detail', 'Unknown error')}")
                
        except Exception as e:
            st.error(f"💥 Connection Refused: Ensure the FastAPI server is running on port 8000.")

else:
    st.write("👈 Provide a Transaction ID in the sidebar to start analysis.")

st.markdown("---")
st.caption("Backend Status: **Operational** | Stack: **Feast, Redis, MLflow, FastAPI**")