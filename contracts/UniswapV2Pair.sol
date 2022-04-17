pragma solidity =0.5.16;

import './interfaces/IUniswapV2Pair.sol';
import './UniswapV2ERC20.sol';
import './libraries/Math.sol';
import './libraries/UQ112x112.sol';
import './interfaces/IERC20.sol';
import './interfaces/IUniswapV2Factory.sol';
import './interfaces/IUniswapV2Callee.sol';

/* 
 * Pair 컨트랙트
 * - 두 개의 토큰에 대한 Pool 컨트랙트
 * - IUniswapV2Pair와 UniswapV2ERC20 계승
 * 
 * IUniswapV2Pair
 * - ERC20와 동일하게 name, symbol, decimals, totalSupply, balanceOf, allowance, approve, transfer, transferFrom 정의
 * - 미구현 함수 존재
 * 
 */

contract UniswapV2Pair is IUniswapV2Pair, UniswapV2ERC20 {
    using SafeMath  for uint;
    using UQ112x112 for uint224;

    uint public constant MINIMUM_LIQUIDITY = 10**3;
    bytes4 private constant SELECTOR = bytes4(keccak256(bytes('transfer(address,uint256)')));

    address public factory;
    address public token0;
    address public token1;

    uint112 private reserve0;           // uses single storage slot, accessible via getReserves
    uint112 private reserve1;           // uses single storage slot, accessible via getReserves
    uint32  private blockTimestampLast; // uses single storage slot, accessible via getReserves

    uint public price0CumulativeLast;
    uint public price1CumulativeLast;
    uint public kLast; // reserve0 * reserve1, as of immediately after the most recent liquidity event

    uint private unlocked = 1;
    modifier lock() {
        require(unlocked == 1, 'UniswapV2: LOCKED');
        unlocked = 0;
        _; // 민트 함수 실행
        unlocked = 1;
    }

    function getReserves() public view returns (uint112 _reserve0, uint112 _reserve1, uint32 _blockTimestampLast) {
        _reserve0 = reserve0;
        _reserve1 = reserve1;
        _blockTimestampLast = blockTimestampLast;
    }

    function _safeTransfer(address token, address to, uint value) private {
        (bool success, bytes memory data) = token.call(abi.encodeWithSelector(SELECTOR, to, value));
        require(success && (data.length == 0 || abi.decode(data, (bool))), 'UniswapV2: TRANSFER_FAILED');
    }

    event Mint(address indexed sender, uint amount0, uint amount1);
    event Burn(address indexed sender, uint amount0, uint amount1, address indexed to);
    event Swap(
        address indexed sender,
        uint amount0In,
        uint amount1In,
        uint amount0Out,
        uint amount1Out,
        address indexed to
    );
    event Sync(uint112 reserve0, uint112 reserve1);

    /* 생성자 함수로 Pair 컨트랙트를 호출하는 factory 주소 저장 */
    constructor() public {
        factory = msg.sender;
    }

    /* 초기값 세팅 함수 - factory 주소 체크 및 Pair를 생성 할 토큰 2개의 주소 저장 */
    // called once by the factory at time of deployment
    function initialize(address _token0, address _token1) external {
        require(msg.sender == factory, 'UniswapV2: FORBIDDEN'); // sufficient check
        token0 = _token0;
        token1 = _token1;
    }

    // update reserves and, on the first call per block, price accumulators
    function _update(uint balance0, uint balance1, uint112 _reserve0, uint112 _reserve1) private {

        /* 오버플로우 체크 */
        require(balance0 <= uint112(-1) && balance1 <= uint112(-1), 'UniswapV2: OVERFLOW');
        
        /* 블록 타임스탬프 가져오기 */
        uint32 blockTimestamp = uint32(block.timestamp % 2**32);

        /* 마지막 업데이트 시점으로부터 현재 시점 (당연히 0보다 커야함) */
        uint32 timeElapsed = blockTimestamp - blockTimestampLast; // overflow is desired

        if (timeElapsed > 0 && _reserve0 != 0 && _reserve1 != 0) {
            /* 
             * 가격 추적 방식
             * - V1에서는 즉각적으로 가격을 가져왔음
             * - V2에서는 시간의 흐름을 파악하여 가격 추적 시스템을 구축
             * - 토큰의 비율을 지나간 초만큼 스케일업 하되 대신 가격을 가져올 때는 다음과 같은 공식을 사용
             * - (price0CumulativeLATEST — price0CumulativeFIRST) / (timestampOfLATEST — timestampOfFIRST)
             * - 시간 차가 클수록 조작하기가 더 어려워지나 최신 정보는 아니게 됨
             * - V1 취약점에 대한 글 : https://medium.com/@epheph/using-uniswap-v2-oracle-with-storage-proofs-3530e699e1d3
             */
            // * never overflows, and + overflow is desired
            price0CumulativeLast += uint(UQ112x112.encode(_reserve1).uqdiv(_reserve0)) * timeElapsed;
            price1CumulativeLast += uint(UQ112x112.encode(_reserve0).uqdiv(_reserve1)) * timeElapsed;
        }

        /* balance만큼 reserve에 대입하고 업데이트 시점 기록 */
        reserve0 = uint112(balance0);
        reserve1 = uint112(balance1);
        blockTimestampLast = blockTimestamp;
        emit Sync(reserve0, reserve1);
    }

    // if fee is on, mint liquidity equivalent to 1/6th of the growth in sqrt(k)
    function _mintFee(uint112 _reserve0, uint112 _reserve1) private returns (bool feeOn) {

        /* factory 컨트랙트의 feeTo 값을 가져옴 */
        address feeTo = IUniswapV2Factory(factory).feeTo();

        /* feeTo가 유효한 주소인 지 체크 - 현재는 미구현으로 false가 나올 것 */
        feeOn = feeTo != address(0);

        /* 
         * 마지막 k의 값
         * - reserve0과 reserve1를 곱한 값
         * - feeOn이 false일 때는 무조건 0으로 설정되어 있음
         */
        uint _kLast = kLast; // gas savings
        if (feeOn) {
            if (_kLast != 0) {
                /* _reserve0과 _reserve1을 곱한 후 k의 루트 값 가져오기 */
                uint rootK = Math.sqrt(uint(_reserve0).mul(_reserve1));
                /* _kLast의 루트 값 가져오기 */
                uint rootKLast = Math.sqrt(_kLast);

                /*
                 * rootK가 rootKLast보다 큰 경우 실행되는 블록
                 * - 두 개의 값이 다를 수 있을까 생각했더니 결과적으로 mint는 토큰이 들어온 후 실행
                 * - 토큰이 들어왔을 때 kLast는 업데이트 되었을 것
                 * - 따라서 rootK는 토큰이 들어오기 전 k의 루트 값
                 */
                if (rootK > rootKLast) {

                    /*
                     * 수수료 구조를 살펴보면,
                     * - 트레이더들은 0.30%의 수수료를 provider에게 제공
                     * - 0.30%의 1/6인 0.05%를 FeeTo 주소에게 내는 것
                     * - 계산 공식은 https://uniswap.org/whitepaper.pdf 5페이지에서 확인 가능
                     * - 매 트레이드 마다 수수료 발생하면 가스비가 많이 나오게 됨
                     * - 따라서 0.05%의 수수료는 모아놨다가 유동성이 공급되거나 소각될 때 계산됨
                     * - 이때의 모아놓은 수수료를 계산하는 공식이 아래와 같음
                     */

                    /* liquidity를 구한 후 해당 값이 0보다 크면 feeTo 주소에 해당 양 만큼 토큰을 발행 */
                    uint numerator = totalSupply.mul(rootK.sub(rootKLast));
                    uint denominator = rootK.mul(5).add(rootKLast);
                    uint liquidity = numerator / denominator;
                    if (liquidity > 0) _mint(feeTo, liquidity);
                }
            }
        } else if (_kLast != 0) {
            kLast = 0;
        }
    }

    /*
     * 발행 함수
     */
    // this low-level function should be called from a contract which performs important safety checks
    function mint(address to) external lock returns (uint liquidity) {

        /* getReserves는 사실상 가스비를 조금 줄이기 위한 방법으로 컨트랙트의 reserve */
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings

        /* 해당 컨트랙트 주소가 보유하고 있는 token0과 token1의 수량을 가져옴 */
        uint balance0 = IERC20(token0).balanceOf(address(this)); 
        uint balance1 = IERC20(token1).balanceOf(address(this));

        /* 
         * token0과 token1의 수량에서 _reserve0과 _reserve1만큼 각각 차감함
         * - _reserve0과 _reserve1은 유저가 공급하기 직전의 balance0과 balance1의 값
         * - amount0과 amount1은 유저가 공급한 토큰의 값
         * - balance0과 balance1은 유저가 토큰을 공급한 후의 컨트랙트가 보유한 값
         */
        uint amount0 = balance0.sub(_reserve0); 
        uint amount1 = balance1.sub(_reserve1);

        /* feeOn - 유동성 공급자가 내야 하는 수수료 여부 확인 및 토큰을 신규 발행하는 방식으로 지급 */
        bool feeOn = _mintFee(_reserve0, _reserve1);

        /* LP 토큰의 수량 가져오기 */
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        
        /* 초기 발행과 아닌 시점의 구분 */
        if (_totalSupply == 0) {
            
            liquidity = Math.sqrt(amount0.mul(amount1)).sub(MINIMUM_LIQUIDITY);

            /* 초기 발행 시 MINIMUM_LIQUIDITY 만큼(10의 3승)은 영구 소각 - 반올림 오류 개선 */
           _mint(address(0), MINIMUM_LIQUIDITY);
        } else {
            liquidity = Math.min(amount0.mul(_totalSupply) / _reserve0, amount1.mul(_totalSupply) / _reserve1);
        }

        /* 양수인지 여부 체크하고 발행자에게 liqudity 만큼 토큰 발행 */
        require(liquidity > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_MINTED');
        _mint(to, liquidity);
 

        _update(balance0, balance1, _reserve0, _reserve1);

        /* fee가 존재하는 경우 kLast 값도 업데이트 함 */
        if (feeOn) kLast = uint(reserve0).mul(reserve1);
        emit Mint(msg.sender, amount0, amount1);
    }

    /*
     * 소각 함수
     * - lock modifier
     * - lock을 일시적으로 unlock 후 함수 실행한다음에 다시 lock을 채움
     * - 자원 공유로 인하여 발생할 수 있는 이슈 방지 (해당 함수를 누군가 실행하고 있을 때 다른 사람은 실행 불가 - 뮤텍스 개념)
     */
    // this low-level function should be called from a contract which performs important safety checks
    function burn(address to) external lock returns (uint amount0, uint amount1) {
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        address _token0 = token0;                                // gas savings
        address _token1 = token1;                                // gas savings

        /* 해당 컨트랙트 주소가 보유하고 있는 token0과 token1의 수량을 가져옴 */
        uint balance0 = IERC20(_token0).balanceOf(address(this));   
        uint balance1 = IERC20(_token1).balanceOf(address(this));

        /* 해당 컨트랙트 주소가 보유하고 유동성(LP 토큰) 물량 가져옴 - 이때 내가 가지고 있는 liquidity 물량이라고 보면 됨 */
        uint liquidity = balanceOf[address(this)];

        /* 발행 및 소각 시에만 수수료 발생 */
        bool feeOn = _mintFee(_reserve0, _reserve1);

        /* 내가 가지고 있는 liquidity의 비율 만큼 컨트랙트에 있는 token0과 token1의 값을 가져와서 amount0, amount1에 저장 */
        uint _totalSupply = totalSupply; // gas savings, must be defined here since totalSupply can update in _mintFee
        amount0 = liquidity.mul(balance0) / _totalSupply; // using balances ensures pro-rata distribution
        amount1 = liquidity.mul(balance1) / _totalSupply; // using balances ensures pro-rata distribution
        require(amount0 > 0 && amount1 > 0, 'UniswapV2: INSUFFICIENT_LIQUIDITY_BURNED');
        
        /* 내가 보낸 liqudity 소각 */
        _burn(address(this), liquidity);

        /* liquidity 소각에 따른 token0과 toekn1을 to에게 amount0, amount1만큼 환급 */
        _safeTransfer(_token0, to, amount0);
        _safeTransfer(_token1, to, amount1);
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));


        _update(balance0, balance1, _reserve0, _reserve1);

        /* fee가 존재하는 경우 kLast 값도 업데이트 함 */
        if (feeOn) kLast = uint(reserve0).mul(reserve1);
        emit Burn(msg.sender, amount0, amount1, to);
    }

    /*
     * 스왑 함수
     * - lock modifier
     * - amount0Out => 나갈 token0의 물량
     * - amount1Out => 나갈 token1의 물량
     * - to => 주소
     * - data => 대출과 상환이 한 번에 일어나는 플래시론일 때 존재하며 그 외에는 length가 0인 데이터가 들어옴
     */
    // this low-level function should be called from a contract which performs important safety checks
    function swap(uint amount0Out, uint amount1Out, address to, bytes calldata data) external lock {
        
        /* amount0Out과 amount1Out 유효값 체크 */
        require(amount0Out > 0 || amount1Out > 0, 'UniswapV2: INSUFFICIENT_OUTPUT_AMOUNT');
        (uint112 _reserve0, uint112 _reserve1,) = getReserves(); // gas savings
        require(amount0Out < _reserve0 && amount1Out < _reserve1, 'UniswapV2: INSUFFICIENT_LIQUIDITY');

        uint balance0;
        uint balance1;


        /*
         * stack too deep errors는 EVM stack의 깊이인 16을 넘어갈 때 발생하는 에러
         */
        { // scope for _token{0,1}, avoids stack too deep errors 
        address _token0 = token0;
        address _token1 = token1;
        require(to != _token0 && to != _token1, 'UniswapV2: INVALID_TO');

        /* token0과 token1을 한꺼번에 보내는 이유는 해당 함수를 호출한 컨트랙트가 비율을 조정하기 위함이 아닌가 싶음 */
        if (amount0Out > 0) _safeTransfer(_token0, to, amount0Out); // optimistically transfer tokens
        if (amount1Out > 0) _safeTransfer(_token1, to, amount1Out); // optimistically transfer tokens
        if (data.length > 0) IUniswapV2Callee(to).uniswapV2Call(msg.sender, amount0Out, amount1Out, data);
        
        /* Balance 초기화 */
        balance0 = IERC20(_token0).balanceOf(address(this));
        balance1 = IERC20(_token1).balanceOf(address(this));
        }
        
        /* amount out 값이 존재한다면 balance 값은 클 것 */
        uint amount0In = balance0 > _reserve0 - amount0Out ? balance0 - (_reserve0 - amount0Out) : 0;
        uint amount1In = balance1 > _reserve1 - amount1Out ? balance1 - (_reserve1 - amount1Out) : 0;
        require(amount0In > 0 || amount1In > 0, 'UniswapV2: INSUFFICIENT_INPUT_AMOUNT');
        
        { // scope for reserve{0,1}Adjusted, avoids stack too deep errors
        uint balance0Adjusted = balance0.mul(1000).sub(amount0In.mul(3));
        uint balance1Adjusted = balance1.mul(1000).sub(amount1In.mul(3));
        require(balance0Adjusted.mul(balance1Adjusted) >= uint(_reserve0).mul(_reserve1).mul(1000**2), 'UniswapV2: K');
        }

        _update(balance0, balance1, _reserve0, _reserve1);
        emit Swap(msg.sender, amount0In, amount1In, amount0Out, amount1Out, to);
    }

    /* reserve를 기준으로 balance의 값이 맞춰지도록 하는 함수 - 차이를 to 주소에 보냄 */
    // force balances to match reserves
    function skim(address to) external lock {
        address _token0 = token0; // gas savings
        address _token1 = token1; // gas savings
        _safeTransfer(_token0, to, IERC20(_token0).balanceOf(address(this)).sub(reserve0));
        _safeTransfer(_token1, to, IERC20(_token1).balanceOf(address(this)).sub(reserve1));
    }
    
    /* balance를 기준으로 reserve의 값이 맞춰지도록 업데이트 하는 함수 */
    // force reserves to match balances
    function sync() external lock {
        _update(IERC20(token0).balanceOf(address(this)), IERC20(token1).balanceOf(address(this)), reserve0, reserve1);
    }
}
