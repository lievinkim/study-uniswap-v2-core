pragma solidity =0.5.16;

import './interfaces/IUniswapV2ERC20.sol';
import './libraries/SafeMath.sol';

contract UniswapV2ERC20 is IUniswapV2ERC20 {
    using SafeMath for uint;

    string public constant name = 'Uniswap V2';
    string public constant symbol = 'UNI-V2';
    uint8 public constant decimals = 18;
    uint  public totalSupply;
    mapping(address => uint) public balanceOf;
    mapping(address => mapping(address => uint)) public allowance;

    bytes32 public DOMAIN_SEPARATOR;
    // keccak256("Permit(address owner,address spender,uint256 value,uint256 nonce,uint256 deadline)");
    bytes32 public constant PERMIT_TYPEHASH = 0x6e71edae12b1b97f4d1f60370fef10105fa2faae0126114a169c64845d6126c9;
    mapping(address => uint) public nonces;

    event Approval(address indexed owner, address indexed spender, uint value);
    event Transfer(address indexed from, address indexed to, uint value);


    /* 
     * 생성자
     * - 체인 ID
     * 
     *
     */
    constructor() public {
        uint chainId;
        assembly {
            chainId := chainid
        }
        DOMAIN_SEPARATOR = keccak256(
            abi.encode(
                keccak256('EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)'),
                keccak256(bytes(name)),
                keccak256(bytes('1')),
                chainId,
                address(this)
            )
        );
    }

    /* 
     * private, internal : 컨트랙트 내부에서 접근 가능. 단, internal은 상속 받은 외부 컨트랙트의 접근 허용
     */

    /* 발행 내부 함수 - 전체 발행량 및 특정 주소의 잔액 증가 */
    function _mint(address to, uint value) internal {
        totalSupply = totalSupply.add(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(address(0), to, value);
    }

    /* 소각 내부 함수 - 전체 발행량 및 특정 주소의 잔액 감소 */
    function _burn(address from, uint value) internal {
        balanceOf[from] = balanceOf[from].sub(value);
        totalSupply = totalSupply.sub(value);
        emit Transfer(from, address(0), value);
    }

    /* 허용 내부 함수 - spender가 owner의 토큰을 value 만큼 이동할 수 있도록 허용해 주는 함수 */
    function _approve(address owner, address spender, uint value) private {
        allowance[owner][spender] = value;
        emit Approval(owner, spender, value);
    }

    /* 전송 내부 함수 - from부터 to로 토큰을 value 만큼 전송 */
    function _transfer(address from, address to, uint value) private {
        balanceOf[from] = balanceOf[from].sub(value);
        balanceOf[to] = balanceOf[to].add(value);
        emit Transfer(from, to, value);
    }

    /* 
     * public, external : 컨트랙트 외부에서 접근 가능. 단, external의 경우 외부에서만 접근 가능하고 내부 불가
     */

    /* 허용 외부 함수 - spender가 msg.sender(= owner)의 토큰을 value 만큼 이동할 수 있도록 허용해 주는 함수 */
    function approve(address spender, uint value) external returns (bool) {
        _approve(msg.sender, spender, value);
        return true;
    }

    /* 전송 외부 함수 - msg.sender(= from)부터 to로 토큰을 value 만큼 전송 */
    function transfer(address to, uint value) external returns (bool) {
        _transfer(msg.sender, to, value);
        return true;
    }

    /* 전송 외부 함수 - msg.sender가 from의 토큰을 approve로 허용 받은 to로 이동 */
    function transferFrom(address from, address to, uint value) external returns (bool) {
        if (allowance[from][msg.sender] != uint(-1)) {
            allowance[from][msg.sender] = allowance[from][msg.sender].sub(value);
        }
        _transfer(from, to, value);
        return true;
    }

    /* 
     * permit 함수 - approve, transferFrom 두 번의 트랜잭션을 한 번에 할 수 있도록 해주는 작업
     * 기존 방식 : 1) approve -> 2) approve confirmed -> 3) transferFrom
     * permit 방식 : 1) permit (사용자가 미리 구해 놓은 서명을 함께 전송하여 allowance를 증가) -> 2) transferFrom
     */
    function permit(address owner, address spender, uint value, uint deadline, uint8 v, bytes32 r, bytes32 s) external {
        require(deadline >= block.timestamp, 'UniswapV2: EXPIRED');  // deadline을 지나지 않도록 조건 (메인넷 브로드캐스트에 너무 올래걸리면, 예를 들면 스왑 시 20분 넘게 걸리면 사용하지 않게)
        bytes32 digest = keccak256(
            abi.encodePacked(
                '\x19\x01',
                DOMAIN_SEPARATOR,
                keccak256(abi.encode(PERMIT_TYPEHASH, owner, spender, value, nonces[owner]++, deadline))
            )
        );
        // ecrecover 함수는 데이터의 해시값과 서명값 v, r, s를 넣으면 데이터를 서명한 owner의 주소 출력
        // owner의 주소가 맞지 않으면 잘못된 서명이라고 출력
        address recoveredAddress = ecrecover(digest, v, r, s);
        require(recoveredAddress != address(0) && recoveredAddress == owner, 'UniswapV2: INVALID_SIGNATURE');
        _approve(owner, spender, value);
    }
}
