echo "updating NeuroMiner website (jupyter book and github pages)"

# from NeuroMiner1.3_Manual directory (should be located in the same parent directory as NeuroMiner_1.3

# remove current _build folder
jupyter-book clean ./docs/ --all

# build new html files (_build folder)
jupyter-book build ./docs 

echo "done"
  


