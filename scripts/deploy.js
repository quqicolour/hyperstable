const hre = require("hardhat");
const TenkStablePairABI = require("../artifacts/contracts/TenkStablePair.sol/TenkStablePair.json");
async function main() {
  const [owner, user1] = await hre.ethers.getSigners();
  console.log("owner:",owner.address,"user1:",user1.address);
  const TestToken = await ethers.getContractFactory("TestToken");
  const TestUSDT =  await TestToken.deploy(
    "Test USDT",
    "TUSDT",
    "8"
  );
  await TestUSDT.deployed();
  console.log("TestUSDT:",TestUSDT.address);

  const TestUSDC=  await TestToken.deploy(
    "Test USDC",
    "TUSDC",
    "6"
  );
  await TestUSDC.deployed();
  console.log("TestUSDC:",TestUSDC.address);

  const TestTT=  await TestToken.deploy(
    "Test TT",
    "TTT",
    "18"
  );
  await TestTT.deployed();
  console.log("TestTT:",TestTT.address);

  const WETHToken = await ethers.getContractFactory("WETH9");
  const WETH = await WETHToken.deploy();
  await WETH.deployed();
  console.log("WETH:",WETH.address);

  /** mian contracts */
  const tenkStableFactory = await ethers.getContractFactory("TenkStableFactory");
  const TenkStableFactory =  await tenkStableFactory.deploy(user1.address);
  await TenkStableFactory.deployed();
  console.log("TenkStableFactory:",TenkStableFactory.address);

  const TestStablePair=await TenkStableFactory.createPair(TestUSDT.address,TestUSDC.address);
  const TestStablePairTx=await TestStablePair.wait();
  if(TestStablePairTx.status === 1){
    console.log("TestStablePair success");
  }else{
    console.log("TestStablePair failure");
  }

  const stablePair=await TenkStableFactory.getThisPair(TestUSDT.address,TestUSDC.address);
  console.log("stablePair:",stablePair);

  const tenkRouter = await ethers.getContractFactory("TenkRouter");
  const TenkRouter =  await tenkRouter.deploy(TenkStableFactory.address,WETH.address);
  await TenkRouter.deployed();
  console.log("TenkRouter:",TenkRouter.address);

  const usdtDecimals = await TestUSDT.decimals();
  const usdcDecimals = await TestUSDC.decimals();

  const MaxApprove="10000000000000000";

  const timestamp = new Date().getTime();
  console.log("Current Timestamp:",timestamp); 

  //approve
  const approve1=await TestUSDT.approve(TenkRouter.address,ethers.utils.parseEther(MaxApprove));
  const approve1Tx=await approve1.wait();
  if(approve1Tx.status === 1){
    console.log("approve1 success");
  }else{
    console.log("approve1 failure");
  }

  const approve2=await TestUSDC.approve(TenkRouter.address,ethers.utils.parseEther(MaxApprove));
  const approve2Tx=await approve2.wait();
  if(approve2Tx.status === 1){
    console.log("approve2 success");
  }else{
    console.log("approve2 failure");
  }

  const getThisPair=await TenkRouter.getPair(TestUSDT.address,TestUSDC.address);
  console.log("getThisPair:",getThisPair);

  const initPair=new ethers.Contract(getThisPair,TenkStablePairABI.abi,owner);

  //Add Liquidity
  const addLiquidity=await TenkRouter.addLiquidity(
    TestUSDT.address,
    TestUSDC.address,
    10000*10**usdtDecimals,
    10000*10**usdcDecimals,
    0,
    0,
    owner.address,
    timestamp
  );
  const addLiquidityTx=await addLiquidity.wait();
  if(addLiquidityTx.status === 1){
    console.log("addLiquidity success");
  }else{
    console.log("addLiquidity failure");
  }

  //get pair balance
  const pairBalance=await initPair.balanceOf(owner.address);
  console.log("Pair balance:",pairBalance);

  const pairApprove=await initPair.approve(TenkRouter.address,pairBalance);
  const pairApproveTx=await pairApprove.wait();
  if(pairApproveTx.status === 1){
    console.log("pairApprove success");
  }else{
    console.log("pairApprove failure");
  }

  //Remove Liquidity
  const removeLiquidity=await TenkRouter.removeLiquidity(
    TestUSDT.address,
    TestUSDC.address,
    999999,
    0,
    0,
    owner.address,
    timestamp
  );
  const removeLiquidityTx=await removeLiquidity.wait();
  if(removeLiquidityTx.status === 1){
    console.log("removeLiquidity success");
  }else{
    console.log("removeLiquidity failure");
  }

  const swapIn1=1000*10**usdtDecimals;
  const swapOutMin1=990*10**usdcDecimals;
  const swapIn2="100000";
  const swapTimestamp = new Date().getTime();
  console.log("Current Timestamp:",swapTimestamp);

  const rawAddresses = [
    TestUSDT.address,
    TestUSDC.address
  ];
  
  // 将这些地址转化为字符串类型
  const stringAddresses = rawAddresses.map(address => address.toString(16));
  console.log("stringAddresses:",stringAddresses);

  const beforeUsdtBalance=await TestUSDT.balanceOf(owner.address);
  const beforeUsdcBalance=await TestUSDC.balanceOf(owner.address);
  console.log("beforeUsdtBalance:",beforeUsdtBalance);
  console.log("beforeUsdcBalance:",beforeUsdcBalance);

  //swap
  const swap=await TenkRouter.swapExactTokensForTokens(
    swapIn1,
    swapOutMin1,
    stringAddresses,
    owner.address,
    swapTimestamp
  );
  const swapTx=await swap.wait();
  if(swapTx.status === 1){
    console.log("swap success");
  }else{
    console.log("swap failure");
  }

  const afterUsdtBalance=await TestUSDT.balanceOf(owner.address);
  const afterUsdcBalance=await TestUSDC.balanceOf(owner.address);
  const user1Balance=await TestUSDC.balanceOf(user1.address);
  console.log("afterUsdtBalance:",afterUsdtBalance);
  console.log("afterUsdcBalance:",afterUsdcBalance);
  console.log("user1Balance:",user1Balance);

}

main().catch((error) => {
  console.error(error);
  process.exitCode = 1;
});