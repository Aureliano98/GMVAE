--This file is taken from Torch tutorial file
-- https://github.com/torch/tutorials/blob/master/A_datasets/svhn.lua



----------------------------------------------------------------------
-- This script downloads and loads the (SVHN) House Numbers dataset
-- http://ufldl.stanford.edu/housenumbers/
----------------------------------------------------------------------
print '==> downloading dataset'

-- Here we download dataset files.

-- Note: files were converted from their original Matlab format
-- to Torch's internal format using the mattorch package. The
-- mattorch package allows 1-to-1 conversion between Torch and Matlab
-- files.

-- The SVHN dataset contains 3 files:
--    + train: training data
--    + test:  test data
--    + extra: extra training data

tar = 'http://torch7.s3-website-us-east-1.amazonaws.com/data/svhn.t7.tgz'

if not paths.dirp('housenumbers') then
   os.execute('wget ' .. tar)
   os.execute('tar xvf ' .. paths.basename(tar))
   os.execute('rm svhn.t7.tgz')
end

train_file = 'housenumbers/train_32x32.t7'
test_file = 'housenumbers/test_32x32.t7'
extra_file = 'housenumbers/extra_32x32.t7'

----------------------------------------------------------------------
print '==> loading dataset'

-- We load the dataset from disk, and re-arrange it to be compatible
-- with Torch's representation. Matlab uses a column-major representation,
-- Torch is row-major, so we just have to transpose the data.

-- Note: the data, in X, is 4-d: the 1st dim indexes the samples, the 2nd
-- dim indexes the color channels (RGB), and the last two dims index the
-- height and width of the samples.
local svhn = {}

loaded = torch.load(train_file,'ascii')
svhn.trainData = {
   data = loaded.X:transpose(3,4),
   labels = loaded.y[1]
}

loaded = torch.load(extra_file,'ascii')
svhn.extraTrainData = {
   data = loaded.X:transpose(3,4),
   labels = loaded.y[1]
}

loaded = torch.load(test_file,'ascii')
svhn.testData = {
   data = loaded.X:transpose(3,4),
   labels = loaded.y[1]
}


return svhn
