pragma solidity =0.5.16;

import './interfaces/IUniswapV2Factory.sol';
import './UniswapV2Pair.sol';

/* 
 * Factory 컨트랙트
 * - Pool 생성 컨트랙트
 * - Pair 컨트랙트는 AAM와 Pool의 토큰 비율을 추적하는 컨트랙트
 */

/* 
 * feeTo : Pool 이용 수수료를 지불하는 주소
 * feeToSetter : feeTo를 설정할 수 있는 주소 (관리자 주소)
 * setFeeTo : feeTo를 설정하는 함수
 * setFeeToSetter : feeToSetter를 설정하는 함수 (관리자 변경)
 * getPair : 파라미터로 들어온 2개의 토큰 주소를 이용하여 해당하는 Pool 컨트랙트 주소
 * allPairs : 모든 토큰 Pair의 Pool 컨트랙트 주소 (파라미터 인덱스에 해당하는 컨트랙트 반환)
 * createPair : 파라미터로 들어온 2개의 토큰 주소를 이용하여 Pool 생성
 */

contract UniswapV2Factory is IUniswapV2Factory {

    /*
     * feeTo는 현재 미구현 상태
     * - 추후 0.05%의 프로토콜 단위 수수료를 도입 할 예정
     * - 부과 대상은 트레이더가 아닌 유동성을 공급자를 고려 중 (LP들의 수익의 일부를 수수료로 책정)
     */
    address public feeTo;
    address public feeToSetter;

    /*
     * getPair는 아래 형식의 map 변수
     * key : address
     * value : map(address => address)
     * IUniswapV2Factory의 구현 부분을 살펴보면 이해하기 쉽다.
     * function getPair(address tokenA, address tokenB) external view returns (address pair);
     * 즉, tokenA와 tokenB의 주소를 차례로 넣어주면 (getPair[tokanA][tokenB]), tokanA와 tokenB의 Pair 주소를 리턴한다.
     *
     * allPairs는 주소의 배열로 Pair Contract가 저장되어 있다.
     */
    mapping(address => mapping(address => address)) public getPair;
    address[] public allPairs;

    event PairCreated(address indexed token0, address indexed token1, address pair, uint);

    constructor(address _feeToSetter) public {
        feeToSetter = _feeToSetter;
    }


    /* allPairs의 배열 길이를 리턴하는 함수로 Pair 컨트랙트의 개수를 의미 */
    function allPairsLength() external view returns (uint) {
        return allPairs.length;
    }

    /* 새로운 토큰 Pair 생성 함수 */
    function createPair(address tokenA, address tokenB) external returns (address pair) {
        require(tokenA != tokenB, 'UniswapV2: IDENTICAL_ADDRESSES'); // tokanA와 tokenB가 동일한 주소이면 안된다는 조건
        (address token0, address token1) = tokenA < tokenB ? (tokenA, tokenB) : (tokenB, tokenA); // 주소가 작은 것부터 token0과 token1에 대입
        require(token0 != address(0), 'UniswapV2: ZERO_ADDRESS'); // token0의 주소가 0이면 안된다는 조건
        require(getPair[token0][token1] == address(0), 'UniswapV2: PAIR_EXISTS'); // 기존에 생성되어 있는 Pair인지 확인 (중복 불가)
        bytes memory bytecode = type(UniswapV2Pair).creationCode; // UniswapV2Pair 컨트랙트의 바이트 코드를 저장 (바이트 코드는 솔리디티로 만든 컨트랙트를 이더리움 네트워크가 인식할 수 있도록 번역한 언어)
        bytes32 salt = keccak256(abi.encodePacked(token0, token1)); // encodePacked로 압축 후 keccak256으로 해시하여 저장
        
        /*
         * 컨트랙트 주소를 생성하는 opcode는 create와 create2가 있음
         * - create : msg.sender의 address와 msg.sender의 nonce를 이용하여 생성 (nonce는 트랜잭션 발생시 1씩 증가하여 중복 사용 불가)
         * - create2 : 0xFF, msg.sender의 address, salt, bytecode 4개를 이용하여 생성 (예측 가능 및 미래에 발생할 수 있는 이벤트로부터 독립적)
         * - create2로 생성하면 주소 예측이 가능하여 트랜잭션 컨펌이 나지 않아도 getPair와 allPairs에 Parameter로 전달 가능
         */
        assembly {
            pair := create2(0, add(bytecode, 32), mload(bytecode), salt) 
        }     
        IUniswapV2Pair(pair).initialize(token0, token1);

        /* 2개의 토큰 주소 입력 순서와 상관없이 항상 같은 pair가 나올 수 있도록 설정 */
        getPair[token0][token1] = pair;
        getPair[token1][token0] = pair; // populate mapping in the reverse direction
        
        allPairs.push(pair); // allPairs 배열에 추가
        emit PairCreated(token0, token1, pair, allPairs.length);
    }

    /* feeTo 값 설정 함수 - 관리자만 가능 */
    function setFeeTo(address _feeTo) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeTo = _feeTo;
    }

    /* 관리자 변경 함수 - 관리자만 가능 */
    function setFeeToSetter(address _feeToSetter) external {
        require(msg.sender == feeToSetter, 'UniswapV2: FORBIDDEN');
        feeToSetter = _feeToSetter;
    }
}
