echo "updating NeuroMiner website (jupyter book and github pages)"

# from NeuroMiner1.3_Manual directory (should be located in the same parent directory as NeuroMiner_1.3

# remove current _build folder
jupyter-book clean ./docs/ --all

# save changes to markdown files to github (as backup)  
git add .
git commit -m 'save manual text changes'
git push 

# build new html files (_build folder)
jupyter-book build ./docs 

# add changes to NeuroMiner_1.3 website (hosted from gh-pages branch)
cd ..
cd NeuroMiner_1.3
git checkout gh-pages
cp -R ../NM_manuals/docs/_build/html/. .
cp -R ../NM_manuals/docs/Downloads .
git add . 
git commit -m 'updating manual website'
git push -u origin gh-pages     
git checkout main 

echo "Done, changes to website should be visible in about 2min"
  


