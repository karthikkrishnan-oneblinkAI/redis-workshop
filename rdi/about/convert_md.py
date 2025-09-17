import markdown
# Open the file for reading and read the input to a temp variable
with open('README.md', 'r') as f:
      tempMd= f.read()

# Convert the input to HTML
tempHtml = markdown.markdown(tempMd)
print(tempHtml)
