from flask import Flask, request

app = Flask(__name__)

words = {
    "Oracle": "Oracle©",
    "Google": "Google©",
    "Microsoft": "Microsoft©",
    "Amazon": "Amazon©",
    "Deloitte": "Deloitte©"}

@app.route('/', methods=['GET'])
def replace_word():
    string = request.args.get("string")
    for word in words.keys():
        if word in string:
            return string.replace(word, words[word])

if __name__ == '__main__':
    app.run(debug=True,host='0.0.0.0', port=5000)