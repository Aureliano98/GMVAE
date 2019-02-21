require 'nn'
require 'optim'
require 'nngraph'
require 'ClusteringEvaluations'
local gnuplot = require 'gnuplot'
local cjson = require 'cjson'
local image = require 'image'

local function normalize(x, eps)
	assert(x:nDimension() == 2)
	
	for i = 1, x:size(1) do
		mu = torch.mean(x[i])
		std = torch.std(x[i]) + eps
		x[i]:add(-mu):div(std)
	end
end

local cmd = torch.CmdLine()
cmd:option('-dataSet', 'mnist', 'Dataset used')
cmd:option('-seed', 1, 'random seed')
cmd:option('-learningRate', 0.0001, 'Learning rate')
cmd:option('-batchSize', 50, 'Batch Size')
cmd:option('-optimiser', 'adam', 'Optimser')
cmd:option('-gpu', 0, 'Using Cuda, 1 to enable')
cmd:option('-epoch', 100, 'Number of Epoch')
cmd:option('-visualise2D', 0, 'Save data for visualisation, 1 to enable')
cmd:option('-xSize', 200, 'Size of x variable')
cmd:option('-wSize', 150, 'Size of w variable')
cmd:option('-K', 15, 'Number of clusters')
cmd:option('-hiddenSize', 500, 'Size of the hidden layer')
cmd:option('-zPriorWeight', 1, 'Weight on the z prior term')
cmd:option('-ACC', 0, 'Report Clustering accuracy')
cmd:option('-visualGen', 0, 'Visualise the generation samples at every [input] epochs (0 to disable)')
cmd:option('-continuous', 0, 'Data is continous use Gaussian Criterion (1), Data is discrete use BCE Criterion (0)')
cmd:option('-inputDimension', 1, 'Dimension of the input vector into the network (e.g. 2 for height x width)')
cmd:option('-network', 'fc', 'Network architecture use: fc (FullyConnected)/ conv (Convolutional AE) .. ')
cmd:option('-nChannels', 1, 'Number of Input channels')
cmd:option('-nFilters', 16, 'Number of Convolutional Filters in first layer')
cmd:option('-nMC', 1, 'Number of monte-carlo sample')
cmd:option('-gpuID', 1, 'Set GPU id to use')
cmd:option('-cvWeight', 1, 'Weight of the information theoretic cost term')
cmd:option('-_id', '', 'Experiment Path')
cmd:option('-saveModel',0, 'Save model in experiments folder after finish training')
cmd:option('-reportLowerBound', 1, 'Save lowerbound while training')
cmd:option('-lambda', 0.5 , 'Free bits threshold')
local opt = cmd:parse(arg)

torch.manualSeed(opt.seed)
torch.setdefaulttensortype('torch.FloatTensor')

-- Set save directory
if not paths.dirp('experiments') then
	paths.mkdir('experiments')
end
if not paths.dirp('save') then
	paths.mkdir('save')
end
paths.mkdir(paths.concat('experiments', opt._id))
-- Save option for reference
local file = torch.DiskFile(paths.concat('experiments', opt._id, 'opts.json'),'w')
file:writeString(cjson.encode(opt))
file:close()

-- Preparing Data --
local dataSet = opt.dataSet-- 'spiral'
local data, label_data, width, height
local y_size

if dataSet == 'mnist' then

	print('Load MNIST')
	local mnist = require 'mnist'
	data = mnist.traindataset().data:float():div(255) -- normalised [0, 1]
	test_data = mnist.testdataset().data:float():div(255)
	test_data_label = mnist.testdataset().label:float()
	test_data_label:add(1)

	width = data:size(3)
	height = data:size(2)
	if opt.inputDimension == 1 then
		data = data:resize(data:size(1), data:size(2)*data:size(3)) -- resize into 1D
		test_data = test_data:resize(test_data:size(1), test_data:size(2)*test_data:size(3))
		y_size = data:size(2)
	else
		y_size = {data:size(2), data:size(3)}
		data = data:resize(data:size(1), 1, data:size(2), data:size(3))
		test_data = test_data:resize(test_data:size(1), 1, test_data:size(2), test_data:size(3))
	end
	-- prepare label for measuring training accuracy
	label_data = mnist.traindataset().label:float()
	label_data:add(1) -- from [0,9] -> [1, 10]

elseif dataSet == 'spiral' then

	-- LYL: actually cannot work properly (visualization part is buggy)
	print('Load Spiral')
	data = torch.load('datasets/spiral.t7'):float()
	y_size = data:size(2)

elseif dataSet == 'fashion-mnist' then
    
	print('Load Fashion-MNIST')
	local fashion_mnist = require 'fashion-mnist'
	
	local train_set = fashion_mnist.traindataset()
	data = train_set.data:float():div(255)
	label_data = train_set.label:float()	
	label_data:add(1 - torch.min(label_data))	--> [1, 10]

	local test_set = fashion_mnist.testdataset()
	test_data = test_set.data:float():div(255)
	test_data_label = test_set.label:float():add(1)	
	test_data_label:add(1 - torch.min(test_data_label))	--> [1, 10]

	if opt.inputDimension ~= 1 then
		print('WARNING: Fashion MNIST only accepts inputDimension = 1')
	end

	-- y_size = {data:size(2), data:size(3)}
    data = data:resize(data:size(1), data:size(2)*data:size(3)) -- resize into 1D
	test_data = test_data:resize(test_data:size(1), test_data:size(2)*test_data:size(3))
	data = torch.cat(data, test_data, 1)
	test_data = nil
	label_data = torch.cat(label_data, test_data_label, 1)
	test_data_label = nil
	y_size = data:size(2)	-- 784

elseif dataSet == 'stl-10' or dataSet == 'cifar-10' or dataSet == 'cifar-100' then
	
	local matio = require 'matio'
	file_map = {['stl-10']='stl10_feature.mat', 
		['cifar-10']='cifar10_feature.mat',
		['cifar-100']='cifar100_feature.mat'}
	file = paths.concat('datasets', file_map[dataSet])
	data = matio.load(file, 'x'):float()
	if data:size(1) < data:size(2) then	-- Kinda ugly...
		print('Transpose data')
		data = data:transpose(1, 2)
	end
	label_data = matio.load(file, 'y'):float()
	label_data = label_data:resize(label_data:nElement())
	
	print(data:size())
	print(label_data:size())
	-- Normalize
	normalize(data, 1e-7)
	
	label_data:add(1 - torch.min(label_data))	--> [1, 10]
	assert(data:size(1) == label_data:size(1))

	y_size = data:size(2)

elseif dataSet == 'svhn' then
	
	local matio = require 'matio'
	train_file = paths.concat('datasets', 'train_gist.mat') 
	test_file = paths.concat('datasets', 'test_gist.mat')
	train_data = matio.load(train_file, 'X')
	train_label = matio.load(train_file, 'Y')
	test_data = matio.load(test_file, 'X')
	test_label = matio.load(test_file, 'Y')
	--[[
	print(train_data:size())
	print(test_data:size())
	print(train_label:size())
	print(test_label:size())
	--]]
	data = torch.cat(train_data, test_data, 1):float()
	label_data = torch.cat(train_label, test_label, 1):float()
	label_data = label_data:resize(label_data:nElement())
	n = data:size(1) - data:size(1) % opt.batchSize 
	data = data:sub(1, n, 1, data:size(2))
	label_data = label_data:sub(1, n)
	test_data = nil
	-- Normalize
	normalize(data, 1e-7)
	--[[
	for i = 1, data:size(1) do
		data[i] = data[i]:sub(torch.mean(data[i]))
			:div(torch.std(data[i]) + 1e-7)
	end
	--]]
	label_data:add(1 - torch.min(label_data))	--> [1, 10]
	assert(data:size(1) == label_data:size(1))

	y_size = data:size(2)

else

	error('Unsupported dataset ' .. dataSet)

end

for k, v in pairs({data=data, label_data=label_data, 
	test_data=test_data, test_data_label=test_data_label}) do
	if v then
		print(k .. ' size: ')
		print(v:size())
	end
end



local N = data:size(1)
local x_size = opt.xSize
local z_size = opt.K
local w_size = opt.wSize
local batch_size = opt.batchSize
local learning_rate = opt.learningRate
local optimiser = opt.optimiser
local max_epoch = opt.epoch
local hidden_size = opt.hiddenSize
local cuda = opt.gpu
local visualise2D = opt.visualise2D
local visualGen = opt.visualGen
local zPriorWeight = opt.zPriorWeight
local reportACC = opt.ACC
local continuous = opt.continuous

require 'UtilsNetwork'
local model
if opt.network == 'fc' then

	model = require 'models/FullyConnected'

elseif opt.network == 'conv' then

	model = require 'models/ConvAE'
	model.nChannels = opt.nChannels
	model.nFilters = opt.nFilters
end

-- Network parts --
local zxw_recogniser = model:CreateRecogniser(y_size, hidden_size, x_size, w_size, z_size)
local y_generator = model:CreateYGenerator(x_size, hidden_size, y_size, continuous)
local prior_generator = model:CreatePriorGenerator(w_size, hidden_size, x_size, z_size)

-- Connect parts together --
local input = - nn.Identity()
local noise1 = - nn.Identity()
local noise2 = - nn.Identity()
local zxw = input - zxw_recogniser
local q_z = zxw - nn.SelectTable(1)
local q_x = zxw - nn.SelectTable(2)
local q_w = zxw - nn.SelectTable(3)
local x_sample = {q_x, noise1} - GaussianSampler(opt.nMC, x_size)
local w_sample = {q_w, noise2} - GaussianSampler(opt.nMC, w_size)
local y_recon  = x_sample - y_generator
local p_xz  = w_sample - prior_generator
local GMVAE = nn.gModule({input, noise1, noise2},{q_z, q_x, q_w, p_xz, y_recon, x_sample})

-- Additional layers to facilitate more than one monte-carlo sample
local MC_replicate = nn.Replicate(opt.nMC)
-- Layers for calculating Likelihood used in calculating CV
local Likelihood = Likelihood(z_size, x_size, opt.nMC)
--

require 'criteria/GaussianCriterion'
require 'criteria/VAE_KLDCriterion'
require 'criteria/DiscreteKLDCriterion'
require 'criteria/EntropyCriterion'

-- Criteria --
local ReconCriterion
if continuous == 1 then
	ReconCriterion = nn.GaussianCriterion()
else
	ReconCriterion = nn.BCECriterion()
	ReconCriterion.sizeAverage = false
end

local ExpectedKLDivergence = ExpectedKLDivergence(z_size, x_size, opt.nMC)
local VAE_KLDCriterion = nn.VAE_KLDCriterion()
local DiscreteKLDCriterion = nn.DiscreteKLDCriterion(zPriorWeight)
local EntropyCriterion = nn.EntropyCriterion(opt.cvWeight, opt.nMC)

-- Set up Cuda
if cuda == 1 then
	require 'cutorch'
	require 'cunn'
	print('Using Cuda')
	local hasCudnn, cudnn = pcall(require, 'cudnn') -- Use cuDNN if available
	cutorch.setDevice(opt.gpuID)
	data = data:cuda() -- load data into GPU

	GMVAE:cuda()
	ReconCriterion:cuda()
	ExpectedKLDivergence:cuda()
	VAE_KLDCriterion:cuda()
	DiscreteKLDCriterion:cuda()

	MC_replicate:cuda()
	EntropyCriterion:cuda()
	Likelihood:cuda()

	if hasCudnn then
		print('Using cudnn')
   		cudnn.convert(GMVAE, cudnn)
  	end
	if test_data then
        test_data = test_data:cuda()
    end
end

local params, gradParams = GMVAE:getParameters()


function feval(params)

	GMVAE:zeroGradParameters()

	local qZ, qX, qW, p_xz, y_recon, x_sample  = table.unpack( GMVAE:forward({y, n1, n2}) )



	-- CALCULATE LOSS AND GRADIENT
 	local y_replicated = MC_replicate:forward(y)

	-- 1.) Reconstruction Cost = -E[logP(y|x)]
	local reconLoss = ReconCriterion:forward(y_recon, y_replicated  ) * (1/opt.nMC)
	local dRecon_dy = ReconCriterion:backward(y_recon, y_replicated )
	if continuous == 1 then
		dRecon_dy[1]:div(opt.nMC)
		dRecon_dy[2]:div(opt.nMC)
	else
		dRecon_dy:div(opt.nMC)
	end


	local xLoss, oneTensor, gradQz, gradMean_x, gradLogVar_x, gradMean_k, gradLogVar_k
	local gradQz, mean_k, logVar_k

	-- 2.) E_z_w[KL(q(x)|| p(x|z,w))]
	local mean_x, logVar_x = table.unpack(qX)
	mean_k, logVar_k = table.unpack(p_xz)
	local KL_out = ExpectedKLDivergence:forward({qZ, mean_x, logVar_x, mean_k, logVar_k})
	xLoss = KL_out:sum()
	oneTensor = oneTensor or torch.Tensor():typeAs(KL_out):resizeAs(KL_out):fill(1)
	gradQz, gradMean_x, gradLogVar_x, gradMean_k, gradLogVar_k =
			table.unpack( ExpectedKLDivergence:backward({qZ, mean_x, logVar_x, mean_k, logVar_k}, oneTensor ) )


	-- 3.) KL( q(w) || P(w) )
	local mean_w, logVar_w = table.unpack(qW)
	local wLoss = VAE_KLDCriterion:forward( mean_w, logVar_w)
	local gradW	= VAE_KLDCriterion:backward( mean_w, logVar_w)

	-- 4.) KL( q(z) || P(z) ) 
	local zLoss = DiscreteKLDCriterion:forward(qZ)
	gradQz:add( DiscreteKLDCriterion:backward(qZ) )


	-- 5.)  CV = H(Z|X, W) = E_q(x,w) [ E_p(z|x,w)[ - log P(z|x,w)] ]
	local lh = Likelihood:forward({x_sample, mean_k, logVar_k})
	local CV = EntropyCriterion:forward(lh)
	local gradLh = EntropyCriterion:backward(lh)
	local gradX, gradM_k, gradLv = table.unpack(Likelihood:backward({x_sample, mean_k, logVar_k}, gradLh))
	for k =1, z_size do
		gradMean_k[k]:add(gradM_k[k])
		gradLogVar_k[k]:add(gradLv[k])
	end

	-- Put all the gradient of the cost into a table
	local gradLoss = { gradQz,
					   { gradMean_x, gradLogVar_x},
					   gradW,
					   { gradMean_k, gradLogVar_k  },
					   dRecon_dy,
					   gradX
					 }

	-- Backprop all the gradient together
	GMVAE:backward({y, n1, n2}, gradLoss)

	local loss = reconLoss + xLoss + wLoss + zLoss
	return {loss, CV}, gradParams
end


local ACC_evaluation = torch.Tensor(max_epoch):zero()
local Class_evaluation = torch.Tensor(max_epoch):zero()
local Train_Class_evaluation = torch.Tensor(max_epoch):zero()
local Train_ACC_evaluation = torch.Tensor(max_epoch):zero()
local Lowerbound = torch.Tensor(max_epoch):zero()
local CV_Cost = torch.Tensor(max_epoch):zero()

for epoch = 1, max_epoch do

	local Noise1 = torch.randn(opt.nMC, N, x_size)
	local Noise2 = torch.randn(opt.nMC, N, w_size)

	if cuda == 1 then
		Noise1 = torch.CudaTensor():resize(opt.nMC, N, x_size):copy(Noise1)
		Noise2 = torch.CudaTensor():resize(opt.nMC, N, w_size):copy(Noise2)
	end

	local indices_all = torch.randperm(N):long()
	local indices = indices_all:split(batch_size)

	local recon, latent, w_latent, labels

	if visualise2D == 1 then
		recon = torch.Tensor():resizeAs(data):zero()
		latent = torch.Tensor():resize(N, x_size):zero()
		w_latent = torch.Tensor():resize(N, w_size):zero()
		labels = torch.Tensor():resize(N):zero()
	end

	if reportACC == 1 then
		labels = torch.Tensor():resize(N,z_size):zero()
	end



	local Loss = 0.0
	local CVLoss = 0.0
	for t,v in ipairs(indices) do

		GMVAE:training()
		xlua.progress(t, #indices)
		y = data:index(1,v)
		n1 = Noise1:index(2,v)
		n2 = Noise2:index(2,v)


		__, loss = optim[optimiser](feval, params, {learningRate = learning_rate })


		if visualise2D == 1 then
			recon[{ { batch_size*(t-1) + 1, batch_size*t },{}}]    = y_generator.output[1]:view(-1,batch_size,y_size)[1]:float()
			latent[{ { batch_size*(t-1) + 1, batch_size*t },{}}] = zxw_recogniser.output[2][1]:float()
			w_latent[{ { batch_size*(t-1) + 1, batch_size*t },{}}] = zxw_recogniser.output[3][1]:float()
			__, labels[{{ batch_size*(t-1) + 1, batch_size*t }}]   = zxw_recogniser.output[1]:max(2)
		end


		if reportACC == 1 then
			-- Collect report label
		  labels[{{ batch_size*(t-1) + 1, batch_size*t },{}}] = zxw_recogniser.output[1]:float()
		end


		Loss = Loss + loss[1][1]
		CVLoss = CVLoss + loss[1][2]
	end
	print("Epoch: " .. epoch .. " Loss: " .. Loss/N )

	if opt.reportLowerBound == 1 then
		Lowerbound[epoch] = -1 * Loss/N
		torch.save(paths.concat('experiments', opt._id, 'lowerbound.t7'), Lowerbound)
		gnuplot.pngfigure(paths.concat('experiments', opt._id, 'lowerbound.png'))
		gnuplot.plot({'Lowerbound', torch.linspace(1,epoch,epoch), Lowerbound[{{1,epoch}}] ,'-'})
		gnuplot.xlabel('Epoch')
		gnuplot.ylabel('Lowerbound')
		gnuplot.plotflush()

		CV_Cost[epoch] = CVLoss/N
		torch.save(paths.concat('experiments', opt._id, 'CV.t7'), CV_Cost)
		gnuplot.pngfigure(paths.concat('experiments', opt._id, 'CV.png'))
		gnuplot.plot({'CV', torch.linspace(1,epoch,epoch), CV_Cost[{{1,epoch}}] ,'-'})
		gnuplot.xlabel('Epoch')
		gnuplot.ylabel('CV')
		gnuplot.plotflush()

		--[[
		if not( dataSet == 'spiral') then
			local labels_statistics = labels:sum(1)
			labels_statistics = labels_statistics/( labels_statistics:sum() + 1e-10 )
			torch.save(paths.concat('experiments', opt._id, 'labels_stats.t7'), labels_statistics)
			gnuplot.pngfigure(paths.concat('experiments', opt._id, 'labels_stats.png'))
			gnuplot.plot({'Label', torch.linspace(1,z_size,z_size), labels_statistics[1] ,'-'})
			gnuplot.xlabel('K')
			gnuplot.ylabel('Percentage')
			gnuplot.plotflush()
		end
		--]]
	end



	if reportACC == 1 then
		local true_label_all = label_data:index(1, indices_all)
		local training_score = AAE_Clustering_Criteria(labels, true_label_all) --ACC(labels, true_label_all)
		print('Training ACC score: '.. training_score)

		GMVAE:evaluate()

		if test_data then
			-- split batchSize for cudnn --
			local N_test = test_data:size(1)
			test_data_set = test_data:split(1000)
			local predict_label_cpu = torch.Tensor():resize(N_test,z_size)

			for t,data  in ipairs(test_data_set) do
				local predict_label =  zxw_recogniser:forward(data)[1]
				predict_label_cpu[{{ 1000*(t-1) + 1, 1000*t },{}}] = predict_label:float()
			end
			local testing_acc_score = AAE_Clustering_Criteria(predict_label_cpu, test_data_label)
			-- Testing ACC score
			print('Testing ACC score: '.. testing_acc_score)

			ACC_evaluation[epoch] = testing_acc_score
			Train_ACC_evaluation[epoch] = training_score
			torch.save(paths.concat('experiments', opt._id, 'acc_score.t7'), ACC_evaluation)
			torch.save(paths.concat('experiments', opt._id, 'train_ACC_score.t7'), Train_ACC_evaluation)
			gnuplot.pngfigure(paths.concat('experiments', opt._id, 'Scores.png'))
			gnuplot.plot({'Unsupervised Clustering ACC', torch.linspace(1,epoch,epoch), ACC_evaluation[{{1,epoch}}] ,'-'},
						 {'Training ACC', torch.linspace(1,epoch,epoch), Train_ACC_evaluation[{{1,epoch}}], '-' }
						 )
			gnuplot.xlabel('Epoch')
			gnuplot.ylabel('Scores')
			gnuplot.plotflush()
		end

	end


	if visualise2D == 1 then
		torch.save('save/ws.t7', w_latent)
		torch.save('save/label.t7', labels)
		torch.save('save/recon.t7', recon)
		torch.save('save/xs.t7', latent)
		GMVAE:evaluate()
		local mean, logVar = table.unpack( prior_generator:forward(torch.Tensor(1, w_size):typeAs(data):zero()) )
		local cov = torch.Tensor(z_size, x_size, x_size)
		local m = torch.Tensor(z_size, x_size)
		for k=1, z_size do
			local var = logVar[k][1]:exp()
	        cov[k] = torch.diag( var )
	        m[k] = mean[k][1]
	    end

	    torch.save('save/m.t7', m)
	    torch.save('save/cov.t7', cov)
	end

	if visualGen > 0 then
		-- Generate data condition on the code every 'visualGen' epoch
		if epoch%visualGen == 0 then
			GMVAE:evaluate()
			-- : Fix w = 0 and vary z from 1 to K,
			-- : Samples 10 x
			local gaussianSampler = GaussianSampler(1, x_size)
			if cuda == 1 then
				gaussianSampler:cuda()
			end
			local samples = torch.Tensor(opt.nChannels, z_size * height, 10 * width):typeAs(data)
			local mean, logVar = table.unpack( prior_generator:forward(torch.Tensor(10, w_size):typeAs(data):zero() ))
			for k=1, z_size do
				local eps = torch.randn(1, mean[k]:size(1), mean[k]:size(2)):typeAs(mean[k])
				local sample_x = gaussianSampler:forward({ {mean[k], logVar[k]}, eps})
				local samples_temp = y_generator:forward(sample_x):view(-1, opt.nChannels, width, height)
				for j = 1, 10 do
					samples[{{}, {(k-1) * height + 1, k * height},{(j-1)*width + 1, j*width}}] = samples_temp[j]
				end
			end
			image.save(paths.concat('experiments', opt._id, 'samples.png'), samples)
		end

	end


end


if opt.saveModel == 1 then
	torch.save(paths.concat('experiments',opt._id,'params.t7'), params)
end
