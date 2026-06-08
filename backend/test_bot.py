import os
os.environ["PROTOCOL_BUFFERS_PYTHON_IMPLEMENTATION"] = "python"
from dotenv import load_dotenv

from langchain_groq import ChatGroq
from langchain_huggingface import HuggingFaceEmbeddings
from langchain_community.vectorstores import Chroma
from langchain.prompts import PromptTemplate
from langchain.chains import create_retrieval_chain
from langchain.chains.combine_documents import create_stuff_documents_chain

load_dotenv()

def main():
    api_key = os.getenv("GEMINI_API_KEY")
    print("Loading AI Engine...")
    
    # Load Local Embeddings and ChromaDB
    embeddings = HuggingFaceEmbeddings(model_name="all-MiniLM-L6-v2")
    vectorstore = Chroma(persist_directory="./chroma_db", embedding_function=embeddings)
    # Load Groq LLM for the Brain
    retriever = vectorstore.as_retriever(search_kwargs={"k": 5})
    llm = ChatGroq(model="llama-3.3-70b-versatile", temperature=0.3, api_key=os.getenv("GROQ_API_KEY"))
    
    # Define Persona
    system_prompt = (
        "You are the digital twin of Muhammad Salman, a Senior Infrastructure Consultant and 5x AWS Certified Developer. "
        "You are professional, knowledgeable, and helpful. "
        "Use the following pieces of retrieved context to answer the question. "
        "If you don't know the answer based on the context, just say that you don't have that information in your knowledge base. "
        "Do not make up information about your projects or skills. "
        "\n\n"
        "Context:\n{context}"
    )
    
    prompt = PromptTemplate.from_template(system_prompt + "\n\nQuestion: {input}\nAnswer:")
    question_answer_chain = create_stuff_documents_chain(llm, prompt)
    rag_chain = create_retrieval_chain(retriever, question_answer_chain)
    
    print("\n--- AI Engine Ready! ---")
    question = "What is your experience with Docker and Kubernetes? Have you built any projects with them?"
    print(f"Question: {question}")
    
    try:
        response = rag_chain.invoke({"input": question})
        print(f"\nDigital Twin Answer:\n{response['answer']}")
    except Exception as e:
        print(f"\nError contacting Gemini for the answer: {e}")

if __name__ == "__main__":
    main()
