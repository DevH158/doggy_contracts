// SPDX-License-Identifier: MIT
pragma solidity >=0.4.21 <8.10.0;

contract DoggyProjectsV1 {
    // 계약서를 배포한 사람. 프로젝트를 진행하는 본인
    address payable public owner;

    // 현재 진행중인 프로젝트의 수
    uint256 ongoingProjects;

    struct ProjectStatus {
        uint256 requestTime;
        uint256 projectDurationInDays;
        uint256 totalFee;
        bool started;
        bool firstPaymentMade;
        bool totalPaymentMade;
        bool clientDone;
        bool projectDone;
    }

    mapping(address => mapping(string => ProjectStatus)) public clientToProject;
    mapping(address => mapping(string => uint256)) public payments;

    // makeAdvancePayment, makeFinalPayment가 아닌 다른 방식으로 돈을 보내면,
    // lostPayments로 돈을 모아두고 owner가 모두 수동으로 정리할 수 있도록 조치
    mapping(address => uint256) public lostPayments;

    uint256 public totalFund;

    bool private initialized;

    function initialize(address _owner) public {
        require(!initialized, "Contract is already initialized");
        initialized = true;
        owner = payable(_owner);
    }

    modifier onlyOwner() {
        require(msg.sender == owner);
        _;
    }

    function startProject(
        address _client,
        string memory _projectName,
        uint256 _projectDurationInDays,
        uint256 _totalFee
    ) public onlyOwner {
        // contract owner가 프로젝트를 등록하는 과정 (프로젝트 진행사가 수수료 지불)
        // 프로젝트는 등록과 동시에 시작하는 것으로 간주
        clientToProject[_client][_projectName] = ProjectStatus(
            block.timestamp,
            _projectDurationInDays,
            _totalFee,
            true,
            false,
            false,
            false,
            false
        );
        ongoingProjects++;
    }

    function closeProject(
        address _client,
        string memory _projectName,
        bool _clientIsOwner
    ) public {
        // 프로젝트가 잘 마무리 되었다고 승인하는 절차
        // 고객이 이 절차를 수행해야 owner가 돈을 빼갈 수 있습니다.
        if (msg.sender != owner) {
            // owner와 클라이언트가 같은 경우 clientDone을 설정할 수 없음
            clientToProject[msg.sender][_projectName].clientDone = true;
        } else {
            clientToProject[_client][_projectName].projectDone = true;
        }

        if (_clientIsOwner) {
            // client와 owner 같은 경우는 테스트인 경우이다.
            // 테스트를 진행할때 돈이 락될 수 있기 때문에 아래와 같은 장치 추가
            clientToProject[msg.sender][_projectName].clientDone = true;
        }
    }

    function getProjectElapsedTime(address _client, string memory _projectName)
        public
        view
        returns (uint256)
    {
        return
            block.timestamp -
            clientToProject[_client][_projectName].requestTime;
    }

    function extendDueDate(
        address _client,
        string memory _projectName,
        uint256 _addDays
    ) public onlyOwner {
        // 프로젝트가 연장될 경우 owner가 프로젝트 정보를 수정
        clientToProject[_client][_projectName].projectDurationInDays =
            clientToProject[_client][_projectName].projectDurationInDays +
            _addDays;
    }

    function makeAdvancePayment(string memory _projectName) public payable {
        // 선금 납부: 이 함수를 호출하면서 Klay를 함께 전송해야 합니다.
        require(
            clientToProject[msg.sender][_projectName].started,
            "this project has not been started yet"
        );
        payments[msg.sender][_projectName] =
            payments[msg.sender][_projectName] +
            msg.value;
        clientToProject[msg.sender][_projectName].firstPaymentMade = true;
    }

    function makePayment(string memory _projectName) public payable {
        // 부족한 금액은 위 함수를 호출하여 지불할때 사용
        require(
            clientToProject[msg.sender][_projectName].started,
            "this project has not been started yet"
        );
        payments[msg.sender][_projectName] =
            payments[msg.sender][_projectName] +
            msg.value;
        clientToProject[msg.sender][_projectName].firstPaymentMade = true;
        // 한번에 모든 비용을 지불한 경우도 있을 수 있다.
        if (
            clientToProject[msg.sender][_projectName].totalFee <=
            payments[msg.sender][_projectName]
        ) {
            clientToProject[msg.sender][_projectName].totalPaymentMade = true;
        }
    }

    function makeFinalPayment(string memory _projectName) public payable {
        // 잔금 납부: 이 함수를 호출하면서 Klay를 함께 전송해야 합니다.
        require(
            clientToProject[msg.sender][_projectName].started,
            "this project has not been started yet"
        );
        payments[msg.sender][_projectName] =
            payments[msg.sender][_projectName] +
            msg.value;
        clientToProject[msg.sender][_projectName].totalPaymentMade = true;
    }

    function getCurrentPayment(address _client, string memory _projectName)
        public
        view
        returns (uint256)
    {
        return payments[_client][_projectName];
    }

    function withdrawPayment(
        address _client,
        string memory _projectName,
        bool _realTransfer
    ) public onlyOwner {
        // 고객측에서 프로젝트가 끝났다고 closeProject를 호출하여 주면 쌓인 프로젝트 금액을 출금할 수 있게 됩니다.
        require(
            clientToProject[_client][_projectName].clientDone,
            "project is not done yet"
        );
        require(
            clientToProject[_client][_projectName].projectDone,
            "project is not done yet"
        );

        uint256 transferAmount = payments[_client][_projectName];

        payments[_client][_projectName] = 0;
        delete clientToProject[_client][_projectName];
        ongoingProjects--;

        // _realTransfer가 아닌 경우 계약서에 돈을 그대로 둡니다. (추후 withdraw 가능)
        if (_realTransfer) {
            (bool success, ) = owner.call{value: transferAmount}("");
            require(success, "fund withdrawal by owner failed");
        } else {
            totalFund = totalFund + transferAmount;
        }
    }

    function withdrawFund(uint256 _amount) public onlyOwner {
        require(totalFund >= _amount, "not enough fund");
        totalFund = totalFund - _amount;
        (bool success, ) = owner.call{value: _amount}("");
        require(success, "fund withdrawal by owner failed");
    }

    receive() external payable {
        lostPayments[msg.sender] = msg.value;
    }

    fallback() external payable {
        lostPayments[msg.sender] = msg.value;
    }

    function transferLostFundTo(
        address _client,
        string memory _projectName,
        uint256 _amount
    ) public onlyOwner {
        // 계약서에서 제공되는 payment 함수가 아닌 계약서로 바로 Klay를 전송한 경우 owner가 수동으로 위 함수를 호출하여
        // lostPayment를 정리해주어야 합니다.
        require(lostPayments[_client] >= _amount, "not enough lost payments");
        lostPayments[_client] = lostPayments[_client] - _amount;
        payments[_client][_projectName] =
            payments[_client][_projectName] +
            _amount;
    }

    function cleanFailedProject(address _client, string memory _projectName)
        public
        payable
    {
        // 프로젝트 기간이 끝났음에도 done status가 되지 않으면,
        // 1. client가 완료되었음을 승인하지 않은 경우,
        // 2. contract owner가 돈을 withdraw하지 않은 경우,
        // 3. 양측 보두 승인하지 않은 경우입니다.
        // 1, 2번 같은 경우 무관심으로 인한 결과로 보고 돈을 자동으로 contract owner로 전송합니다.
        // 3번 같은 경우 프로젝트 진행 중 문제가 발생한 것으로 보고 일정 시간이 지나고 나서는 payment에 쌓인 금액의 50퍼센트씩 transfer합니다.

        // 프로젝트 완료 후 4일이 지나도 아무 액션이 없는 경우 쌓인 금액의 50%씩 owner / client에게로 보내기
        require(
            msg.sender == owner || msg.sender == _client,
            "only owner or project client can call this function"
        );

        uint256 startTime = clientToProject[_client][_projectName].requestTime;
        uint256 elapsedTime = getProjectElapsedTime(_client, _projectName);
        uint256 projectDuration = clientToProject[_client][_projectName]
            .projectDurationInDays;
        require(
            elapsedTime >= projectDuration * 24 * 60 * 60,
            "project is not over yet"
        );

        uint256 cutTime = 4 * 24 * 60 * 60;
        require(
            block.timestamp - (startTime + elapsedTime) >= cutTime,
            "cannot clean project yet, need to wait 4 days"
        );

        // client에게로 50%의 금액 보내기
        uint256 payment = payments[_client][_projectName];

        payments[_client][_projectName] = 0;
        delete clientToProject[_client][_projectName];
        ongoingProjects--;

        (bool success1, ) = payable(_client).call{value: payment / 2}("");
        require(success1, "payment transfer to client failed");

        (bool success2, ) = owner.call{value: payment / 2}("");
        require(success2, "payment transfer to owner failed");
    }
}
