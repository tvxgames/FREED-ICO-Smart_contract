pragma solidity ^0.4.11;

/**
 * @title SafeMath
 * @dev Math operations with safety checks that throw on error
 */
library SafeMath {
  function mul(uint256 a, uint256 b) internal constant returns (uint256) {
    uint256 c = a * b;
    assert(a == 0 || c / a == b);
    return c;
  }

  function div(uint256 a, uint256 b) internal constant returns (uint256) {
    // assert(b > 0); // Solidity automatically throws when dividing by 0
    uint256 c = a / b;
    // assert(a == b * c + a % b); // There is no case in which this doesn't hold
    return c;
  }

  function sub(uint256 a, uint256 b) internal constant returns (uint256) {
    assert(b <= a);
    return a - b;
  }

  function add(uint256 a, uint256 b) internal constant returns (uint256) {
    uint256 c = a + b;
    assert(c >= a);
    return c;
  }
}

/**
 * @title Ownable
 * @dev The Ownable contract has an owner address, and provides basic authorization control
 * functions, this simplifies the implementation of "user permissions".
 */
contract Ownable {
  address public owner;


  /**
   * @dev The Ownable constructor sets the original `owner` of the contract to the sender
   * account.
   */
  function Ownable() public {
    owner = msg.sender;
  }


  /**
   * @dev Throws if called by any account other than the owner.
   */
  modifier onlyOwner() {
    require(msg.sender == owner);
    _;
  }


  /**
   * @dev Allows the current owner to transfer control of the contract to a newOwner.
   * @param newOwner The address to transfer ownership to.
   */
  function transferOwnership(address newOwner) onlyOwner public{
    require(newOwner != address(0));
    owner = newOwner;
  }

}

/**
 * @title Pausable
 * @dev Base contract which allows children to implement an emergency stop mechanism.
 */
contract Pausable is Ownable {
  event Pause();
  event Unpause();

  bool _paused = false;

  function paused() public constant returns(bool)
  {
    return _paused;
  }


  /**
   * @dev modifier to allow actions only when the contract IS paused
   */
  modifier whenNotPaused() {
    require(!paused());
    _;
  }

  /**
   * @dev called by the owner to pause, triggers stopped state
   */
  function pause() onlyOwner public {
    require(!_paused);
    _paused = true;
    Pause();
  }

  /**
   * @dev called by the owner to unpause, returns to normal state
   */
  function unpause() onlyOwner public {
    require(_paused);
    _paused = false;
    Unpause();
  }
}


//Интерфейс контракта по переводу текущих токенов в другие
contract MigrationAgent
{
    function migrateFrom(address _from, uint256 _value) public;
}



contract Token is Pausable{
  using SafeMath for uint256;

  string public constant name = "FREEDcoin";
  string public constant symbol = "FRD";
  uint8 public constant decimals = 18;

  uint256 public totalSupply;

  mapping(address => uint256) balances;
  mapping (address => mapping (address => uint256)) allowed;

  mapping (address => bool) public unpausedWallet;

  bool public mintingFinished = false;

  uint256 public totalMigrated;
  address public migrationAgent;

  event Transfer(address indexed from, address indexed to, uint256 value);
  event Approval(address indexed owner, address indexed spender, uint256 value);

  event Mint(address indexed to, uint256 amount);
  event MintFinished();

  event Migrate(address indexed _from, address indexed _to, uint256 _value);

  modifier canMint() {
    require(!mintingFinished);
    _;
  }

  //баланс указанного адрес
  function balanceOf(address _owner) public constant returns (uint256 balance) {
    return balances[_owner];
  }

  //перевод токенов со своего счета на другой
  function transfer(address _to, uint256 _value) public whenNotPaused returns (bool) {
    require (_value > 0);
    balances[msg.sender] = balances[msg.sender].sub(_value);
    balances[_to] = balances[_to].add(_value);
    Transfer(msg.sender, _to, _value);
    return true;
  }

  //Возвращает колличество токенов которые _owner доверил истратить со своего счета _spender
  function allowance(address _owner, address _spender) public constant returns (uint256 remaining) {
    return allowed[_owner][_spender];
  }

  //Доверить _sender истратить со своего счета _value токенов
  function approve(address _spender, uint256 _value) public returns (bool) {

    // To change the approve amount you first have to reduce the addresses`
    //  allowance to zero by calling `approve(_spender, 0)` if it is not
    //  already 0 to mitigate the race condition described here:
    //  https://github.com/ethereum/EIPs/issues/20#issuecomment-263524729
    require((_value == 0) || (allowed[msg.sender][_spender] == 0));

    allowed[msg.sender][_spender] = _value;
    Approval(msg.sender, _spender, _value);
    return true;
  }

  //Перевод токенов с доверенного адреса _from на адрес _to в колличестве _value
  function transferFrom(address _from, address _to, uint256 _value) public whenNotPaused returns (bool) {
    var _allowance = allowed[_from][msg.sender];

    // Check is not needed because sub(_allowance, _value) will already throw if this condition is not met
    // require (_value <= _allowance);

    require (_value > 0);

    balances[_from] = balances[_from].sub(_value);
    balances[_to] = balances[_to].add(_value);
    allowed[_from][msg.sender] = _allowance.sub(_value);
    Transfer(_from, _to, _value);
    return true;
  }

  //Выпуск новых токенов на адресс _to в колличестве _amount. Доступна владельцу контракта (контракту Crowdsale)
  function mint(address _to, uint256 _amount) public onlyOwner canMint returns (bool) {
    totalSupply = totalSupply.add(_amount);
    balances[_to] = balances[_to].add(_amount);
    Mint(_to, _amount);
    Transfer(0x0, _to, _amount);
    return true;
  }

  //Прекратить выпуск токенов. Отменить не возможно. Доступна владельцу контракта.
  function finishMinting() public onlyOwner returns (bool) {
    mintingFinished = true;
    MintFinished();
    return true;
  }

  //Переопределение метода возращающего статус паузы обмена/торгов. Никогда для владельца unpaused wallet.
  function paused() public constant returns(bool){
      return super.paused() && !unpausedWallet[msg.sender];
    }


    //Добавить кошелек игнорирующий остановку обмена/торгов. Доступна владельцу контракта.
    function addUnpausedWallet(address _wallet) public onlyOwner {
        unpausedWallet[_wallet] = true;
    }

    //Убрать кошелек игнорирующий остановку обмена/торгов. Доступна владельцу контракта.
    function delUnpausedWallet(address _wallet) public onlyOwner {
         unpausedWallet[_wallet] = false;
    }

    //Включить перевод текуших токенов в другие. Отключить не возможно. Доступна владельцу контракта.
    function setMigrationAgent(address _migrationAgent) public onlyOwner {
        require(migrationAgent == 0x0);
        migrationAgent = _migrationAgent;
    }

    //Перевыпустить свои токены.
    function migrate() public
    {
        uint256 value = balances[msg.sender];
        require(value > 0);

        totalSupply = totalSupply.sub(value);
        totalMigrated = totalMigrated.add(value);
        MigrationAgent(migrationAgent).migrateFrom(msg.sender, value);
        Migrate(msg.sender,migrationAgent,value);
        balances[msg.sender] = 0;
    }
}


//Контракт заморозки средств инвесторов
contract RefundVault is Ownable {
  using SafeMath for uint256;

  enum State { Active, Refunding, Closed }

  mapping (address => uint256) public deposited;
  State public state;

  event Closed();
  event RefundsEnabled();
  event Refunded(address indexed beneficiary, uint256 weiAmount);

  function RefundVault() public {
    state = State.Active;
  }

  //Внесение средств от имени investor. Доступна владельцу контракта (Контракту Crowdsale)
  function deposit(address investor) onlyOwner public payable {
    require(state == State.Active);
    deposited[investor] = deposited[investor].add(msg.value);
  }

  //Получить собранные средства на указанный адрес. Доступна владельцу контракта.
  function close(address _wallet) onlyOwner public {
    require(state == State.Active);
    require(_wallet != 0x0);
    state = State.Closed;
    Closed();
    _wallet.transfer(this.balance);
  }

  //Включить возврат средств инвесторам. Доступна владельцу контракта.
  function enableRefunds() onlyOwner public {
    require(state == State.Active);
    state = State.Refunding;
    RefundsEnabled();
  }

  //Вернуть средства указанному инвестору.
  function refund(address investor) public {
    require(state == State.Refunding);
    uint256 depositedValue = deposited[investor];
    deposited[investor] = 0;
    investor.transfer(depositedValue);
    Refunded(investor, depositedValue);
  }

  //Уничтожение контракта с возвратом средств на указанный адрес. Доступна владельцу контракта.
  function del(address _wallet) public onlyOwner{
    selfdestruct(_wallet);
  }
}

contract Crowdsale{
    using SafeMath for uint256;

    enum ICOType {preSale, sale}
    enum Roles {beneficiary,accountant,manager,observer,bounty,company,team}

    Token public token;

    bool public isFinalized = false;
    bool public isInitialized = false;
    bool public isPausedCrowdsale = false;

    mapping (uint8 => address) public wallets;

    uint256 public maxProfit;
    uint256 public minProfit;
    uint256 public stepProfit;

    uint256 public startTime;
    uint256 public endDiscountTime;
    uint256 public endTime;

    uint256 public rate;
    uint256 ethWeiRaised;
    uint256 nonEthWeiRaised;
    uint256 weiPreSale;
    uint256 public tokenReserved;

    uint256 public softCap;
    uint256 public hardCap;
    uint256 public overLimit;
    uint256 public minPay;

    RefundVault public vault;
    SVTAllocation public lockedAllocation;

    ICOType ICO = ICOType.preSale;

    uint256 allToken;

    bool public team = false;
    bool public company = false;
    bool public bounty = false;
    bool public partners = false;






    event TokenPurchase(address indexed purchaser, address indexed beneficiary, uint256 value, uint256 amount);

    event Finalized();
    event Initialized();

    function Crowdsale(uint256 _value) public
    {
        //Время старта ICO по умолчаниюж
        uint256 time = now + 5 minutes;

        //TODO вернуть
        //require(_token != 0x0);

        //Заполнение адресов кошельков
        wallets[uint8(Roles.beneficiary)] = msg.sender;
        wallets[uint8(Roles.accountant)] = msg.sender;
        wallets[uint8(Roles.manager)] = msg.sender;
        wallets[uint8(Roles.observer)] = msg.sender;
        wallets[uint8(Roles.bounty)] = msg.sender;
        wallets[uint8(Roles.company)] = msg.sender;
        wallets[uint8(Roles.team)] = msg.sender;

        //Параметы: Время старта, время окончания скидки, время окончания раунда
        changePeriod(time, time + 10 minutes, time + 10 minutes);

        //Параметры: минимальная, максимальная цель сблора средств в ETH
        changeTargets(0, 10 finney);

        //Параметры: базовое количество токенов за 1 eth, максимальное превшение HardCap для последней ставки, минимальная ставка
        changeRate(2000000, 1 finney,1 finney);

        //% минимальный бонус, %максимальный бонус, кол-во шагов снижения бонуса
        changeDiscount(0,0,0);

        token = new Token();

        token.pause();

        token.mint(msg.sender,_value);

        token.addUnpausedWallet(msg.sender);

        //Контракт возврата средств инвесторам
        vault = new RefundVault();
    }

    //Возвращает в текстовом виде название текущего раунда. Константная.
    function ICOSaleType()  public constant returns(string){
        return (ICO == ICOType.preSale)?'pre ICO':'ICO';
    }

    //Переводит средства инвестора на контракт возврата средсв. Внутрянняя.
    function forwardFunds() internal {
        vault.deposit.value(msg.value)(msg.sender);
    }

    //Проверка на возможность покупки токенов. Внутрянняя. Константная.
    function validPurchase() internal constant returns (bool) {

        //раунд начался и не закончился
        bool withinPeriod = (now >= startTime && now <= endTime);

        //ставка больше или равна минимальной
        bool nonZeroPurchase = msg.value >= minPay;

        //hardCap не достигнут, и в случае совершения транзакции не будет превышен больше чем на OverLimit
        //Именно в таком виде: weiRaised в правой части. Если weiRaised >= hardCap throw в sub.
        bool withinCap = msg.value <= hardCap.sub(weiRaised()).add(overLimit);

        //ICO инициализировано, не пауза торгов не установлена
        return withinPeriod && nonZeroPurchase && withinCap && isInitialized && !isPausedCrowdsale;
    }

    //Проверка на возможность финализировать ICO Константная.
    function hasEnded() public constant returns (bool) {

        //раунд закончился
        bool timeReached = now > endTime;

        //или достигнут hardCap
        bool capReached = weiRaised() >= hardCap;

        //раунд должен быть инициализирован
        return (timeReached || capReached) && isInitialized;
    }

    //Финализация. Доступна менеджеру, бенефицару, в случае провала всем.
    function finalize() public {

        //Если раунд не провален вызывает только менеджер, кто угодно в противном случае
        require(wallets[uint8(Roles.manager)] == msg.sender || wallets[uint8(Roles.beneficiary)] == msg.sender|| !goalReached());

        //Еще не финализирован
        require(!isFinalized);

        //Может быть финализирован
        require(hasEnded());

        //Устанавливается флаг финализации
        isFinalized = true;

        //Тут логика
        finalization();

        //Генерируем событие
        Finalized();
    }

    //Логика. Внутрянняя.
    function finalization() internal {

        //Если успешно
        if (goalReached()) {

            //отдаем ether бенифицару
            vault.close(wallets[uint8(Roles.beneficiary)]);

            //если есть что отдавать
            if(tokenReserved > 0){

                //Эмиссируем токены non-eth инвесторов на счет бухгалтера
                token.mint(wallets[uint8(Roles.accountant)],tokenReserved);

                //Сбрасываем счетчик
                tokenReserved = 0;
            }

            //Если первый раунд
            if (ICO == ICOType.preSale) {

                //Сбрасываем параметры
                isInitialized = false;
                isFinalized = false;

                //Переключаем на второй раунд
                ICO = ICOType.sale;

                //сбрасываем счетчик сбора средств
                weiPreSale = weiRaised();
                ethWeiRaised = 0;
                nonEthWeiRaised = 0;

                //создаем заново контракт возврата средств
                vault = new RefundVault();


            }else{//Если второй раунд

                //Записываем сколько токенов мы собрали
                allToken = token.totalSupply();

                //Разрешаем забрать токены тем кому можно их забрать
                team = true;
                company = true;
                bounty = true;
                partners = true;
            }
        }else{//если провалили ICO

            //разрешаем забрать инвесторам свои средства
            vault.enableRefunds();
        }
    }

    //Менеджер замораживает токены для команды.
    function finalize1()  public{
        require(wallets[uint8(Roles.manager)] == msg.sender);
        require(team);
        team = false;
        lockedAllocation = new SVTAllocation(token, wallets[uint8(Roles.team)]);
        token.mint(lockedAllocation,allToken.mul(12).div(80));
    }

    //Менеджер переводит токены на оборот компании
    function finalize2() public{
        require(wallets[uint8(Roles.manager)] == msg.sender);
        require(company);
        company = false;
        token.mint(wallets[uint8(Roles.company)],allToken.mul(5).div(80));

    }

    //Менеджер переводит средства на адрес bounty
    function finalize3() public{
        require(wallets[uint8(Roles.manager)] == msg.sender);
        require(bounty);
        bounty = false;
        token.mint(wallets[uint8(Roles.bounty)],allToken.mul(2).div(80));
    }

    //Менеджер переводит бухгалтеру средства для маркетинговых партнеров
    function finalize4() public{
        require(wallets[uint8(Roles.manager)] == msg.sender);
        require(partners);
        partners = false;
        token.mint(wallets[uint8(Roles.accountant)],allToken.mul(1).div(80));
    }

    //Инициализация раунда. Доступна менеджеру.
    function initialize() public{

        //Только менеджер
        require(wallets[uint8(Roles.manager)] == msg.sender);

        //Если еще не инициализированно
        require(!isInitialized);

        //И указанное время старта еще не наступило
        require(now <= startTime);

        //Выполняем логику
        initialization();

        //Генерируем событие
        Initialized();

        //Ставим флаг
        isInitialized = true;
    }

    function initialization() internal {

    }

    //По запросу инвестора, возращаем ему средства.
    function claimRefund() public{
        vault.refund(msg.sender);
    }

    //Проверяем собрали ли мы необходимый минимум средств. Константная.
    function goalReached() public constant returns (bool) {
        return weiRaised() >= softCap;
    }

    function setup(uint256 _startTime, uint256 _endDiscountTime, uint256 _endTime, uint256 _softCap, uint256 _hardCap, uint256 _rate, uint256 _overLimit, uint256 _minPay, uint256 _minProfit, uint256 _maxProfit, uint256 _stepProfit) public{
            changePeriod(_startTime, _endDiscountTime, _endTime);

            //Параметры: минимальная, максимальная цель сблора средств в ETH
            changeTargets(_softCap, _hardCap);

            //Параметры: базовое количество токенов за 1 eth, максимальное превшение HardCap для последней ставки, минимальная ставка
            changeRate(_rate, _overLimit, _minPay);

            //% минимальный бонус, %максимальный бонус, кол-во шагов снижения бонуса
            changeDiscount(_minProfit, _maxProfit, _stepProfit);
    }
    //Меняем дату и время
    //      начала раунда
    //      конца действия бонуса
    //      конца раунда
    //Доступна менеджеру
    function changePeriod(uint256 _startTime, uint256 _endDiscountTime, uint256 _endTime) public{
        //Только менеджер
        require(wallets[uint8(Roles.manager)] == msg.sender);

        //Если не инициализировали раунд
        require(!isInitialized);

        //Дата и время корректны
        require(now <= _startTime);
        require(_endDiscountTime > _startTime && _endDiscountTime <= _endTime);

        //заполняем
        startTime = _startTime;
        endTime = _endTime;
        endDiscountTime = _endDiscountTime;

    }

    //Меняем цели сбора средств. Доступна менеджеру.
    function changeTargets(uint256 _softCap, uint256 _hardCap) public {

        //Только менеджер
        require(wallets[uint8(Roles.manager)] == msg.sender);

        //Если не инициализирован раунд
        require(!isInitialized);

        //Параметры корректны
        require(_softCap <= _hardCap);



        softCap = _softCap;
        hardCap = _hardCap;
    }

    //Меняем цену (кол-во токенов за 1 eth),
    //максимальное превышение hardCap для последней ставки,
    //минимальную ставку
    //Доступна менеджеру
    function changeRate(uint256 _rate, uint256 _overLimit, uint256 _minPay) public {

        //только менеджер
         require(wallets[uint8(Roles.manager)] == msg.sender);

         //если не инициализированно
         require(!isInitialized);

         //цена корректна
         require(_rate > 0);

         //устанавливаем параметры
         rate = _rate;
         overLimit = _overLimit;
         minPay = _minPay;
    }

    //Меняем параметры скидки
    // % мин бонус
    // % макс бонус
    // кол-во шагов
    // Доступна менеджеру
    function changeDiscount(uint256 _minProfit, uint256 _maxProfit, uint256 _stepProfit) public {

        //Только менеджер
        require(wallets[uint8(Roles.manager)] == msg.sender);

        //Раунд еще не инициализирован
        require(!isInitialized);

        //параметры корректны
        //Если _maxProfit < _minProfit throw в sub
        require(_stepProfit <= _maxProfit.sub(_minProfit));

        //Если не ноль шагов
        if(_stepProfit > 0){
            //поставим такой максимальный процент при котором можно обеспечить указанное число шагов без дробных частей
            maxProfit = _maxProfit.sub(_minProfit).div(_stepProfit).mul(_stepProfit).add(_minProfit);
        }else{
            //на ноль делить нельзя считаем что бонус статичен
            maxProfit = _minProfit;
        }

        //устанавливаем остальные параметры
        minProfit = _minProfit;
        stepProfit = _stepProfit;
    }

    //Собранно средств за текущий раунд. Константная.
    function weiRaised() public constant returns(uint256){
        return ethWeiRaised.add(nonEthWeiRaised);
    }

    //Возвращает сумму сборов за оба этапа. Константная.
    function weiTotalRaised() public constant returns(uint256){
        return weiPreSale.add(weiRaised());
    }

    //Возвращает процент бонуса на текущую дату. Константная.
    function getProfitPercent() public constant returns (uint256){
        return getProfitPercentForData(now);
    }

    //возвращает процент бонуса на заданную дату. Константная.
    function getProfitPercentForData(uint256 timeNow) public constant returns (uint256)
    {
        //если скидка 0 или ноль шагов, или раунд не стартовал, возвращаем минимальную скидку
        if(maxProfit == 0 || stepProfit == 0 || timeNow > endDiscountTime){
            return minProfit.add(100);
        }

        //если раунд закончился максимальную
        if(timeNow<=startTime){
            return maxProfit.add(100);
        }

        //период действия бонуса
        uint256 range = endDiscountTime.sub(startTime);

        //дельта процента бонуса
        uint256 profitRange = maxProfit.sub(minProfit);

        //Осталось времени
        uint256 timeRest = endDiscountTime.sub(timeNow);

        //разбивам дельту времени на
        uint256 profitProcent = profitRange.div(stepProfit).mul(timeRest.mul(stepProfit.add(1)).div(range));
        return profitProcent.add(minProfit).add(100);
    }

    //Завершает preICO переводом указанного кол-ва токенов на кошелек бухгалтера. Доступна менеджеру.
    function fastICO(uint256 _totalSupply) public {
      require(wallets[uint8(Roles.manager)] == msg.sender);
      require(ICO == ICOType.preSale && !isInitialized);
      token.mint(wallets[uint8(Roles.accountant)], _totalSupply);
      ICO = ICOType.sale;
    }

    //Снятие с паузы обмена/торгов. Доступна менеджеру, или всем через 4 месяца после успешного окончания ICO
    function tokenUnpause() public {
        require(wallets[uint8(Roles.manager)] == msg.sender || (now > endTime + 120 days && ICO == ICOType.sale && isFinalized && goalReached()));
        token.unpause();
    }

    //Пауза обмена торгов. Доступна менеджеру пока ICO не завершено.
    function tokenPause() public {
        require(wallets[uint8(Roles.manager)] == msg.sender && !isFinalized);
        token.pause();
    }

    //Пауза продаж. Доступна менеджеру.
    function crowdsalePause() public {
        require(wallets[uint8(Roles.manager)] == msg.sender);
        require(isPausedCrowdsale == false);
        isPausedCrowdsale = true;
    }

    //Снятие с паузы продаж. Доступна менеджеру.
    function crowdsaleUnpause() public {
        require(wallets[uint8(Roles.manager)] == msg.sender);
        require(isPausedCrowdsale == true);
        isPausedCrowdsale = false;
    }

    //Проверка имеет ли права адресс игнорировать паузу обмена/торгов. Внутрянняя. Константная.
    function unpausedWallet(address _wallet) internal constant returns(bool){
        bool _accountant = wallets[uint8(Roles.accountant)] == _wallet;
        bool _company = wallets[uint8(Roles.company)] == _wallet;
        bool _bounty = wallets[uint8(Roles.bounty)] == _wallet;
        return _accountant || _company || _bounty;
    }

    //Включить перевыпуск токенов. Отменить не возможно. Доступна менеджеру.
    function moveTokens(address _migrationAgent) public{
        require(wallets[uint8(Roles.manager)] == msg.sender);
        token.setMigrationAgent(_migrationAgent);
    }

    //Изменить адресс для указанной роли.
    //Доступна любому владельцу кошелька кроме наблюдателя.
    //Доступна менеджеру пока раунд не инициализирован.
    //Кошелек наблюдателя менеджер может изменить в любое время.
    function changeWallet(Roles _role, address _wallet) public
    {
        require((msg.sender == wallets[uint8(_role)] && _role != Roles.observer)||(msg.sender == wallets[uint8(Roles.manager)] && (!isInitialized || _role == Roles.observer)));
        address oldWallet = wallets[uint8(_role)];
        wallets[uint8(_role)] = _wallet;
        if(!unpausedWallet(oldWallet))
            token.delUnpausedWallet(oldWallet);
        if(unpausedWallet(_wallet))
            token.addUnpausedWallet(_wallet);
    }

    //Если что-то пошло не так, через год после ICO можно принудительно вернуть замороженные средства инвесторов. Доступна бенифицару.
    function distructVault() public{
        require(wallets[uint8(Roles.beneficiary)] == msg.sender);
        require(now > startTime + 400 /*days*/);
        vault.del(wallets[uint8(Roles.beneficiary)]);
    }

    //Внести информацию о non-ETH инвесторах. Доступна наблюдателю.
    function paymentsInOtherCurrency(uint256 _token, uint256 _value) public{
        require(wallets[uint8(Roles.observer)] == msg.sender);
        bool withinPeriod = (now >= startTime && now <= endTime);
        //Именно в таком виде: weiRaised в правой части. Если weiRaised >= hardCap throw в sub.
        bool withinCap = _value.add(ethWeiRaised) <= hardCap.add(overLimit);
        require(withinPeriod && withinCap && isInitialized);

        nonEthWeiRaised = _value;
        tokenReserved = _token;

    }


    //TODO выпилить
    //Меняет все кошельки кроме тех адрес которых 0x0. 0x0 оставит со старыми значениями
    function GodWallet(address _beneficiary,
    address _accountant,
    address _manager,
    address _observer,
    address _bounty,
    address _company,
    address _team) public
    {
        if(_beneficiary != 0x0){
            wallets[uint8(Roles.beneficiary)] = _beneficiary;
        }
        if(_accountant != 0x0){
            token.delUnpausedWallet(wallets[uint8(Roles.accountant)]);
            wallets[uint8(Roles.accountant)] = _accountant;
            token.delUnpausedWallet(_accountant);
        }
        if(_manager != 0x0){
            wallets[uint8(Roles.manager)] = _manager;
        }
        if(_observer != 0x0){
            wallets[uint8(Roles.observer)] = _observer;
        }
        if(_bounty != 0x0){
            token.delUnpausedWallet(wallets[uint8(Roles.bounty)]);
            wallets[uint8(Roles.bounty)] = _bounty;
            token.delUnpausedWallet(_bounty);
        }
        if(_company != 0x0){
            token.delUnpausedWallet(wallets[uint8(Roles.company)]);
            wallets[uint8(Roles.company)] = _company;
            token.delUnpausedWallet(_company);
        }
        if(_team != 0x0){
            wallets[uint8(Roles.team)] = _team;
        }
    }

    //TODO выпилить
    //_restartVault true - перезапустить
    //_ICOType false preSale, true sale
    //_ethWeiRaised и _nonEthWeiRaisedn = 1 оставит значение без изменений
    //_newToken = 0x0 оставит без изменений
    //_newAllocation = 0x0 оставит без изменений
    function GodMode(bool _isInitialized,bool _isFinalized, bool _restartVault, bool _ICOType, uint256 _ethWeiRaised,uint256 _nonEthWeiRaised, address _newToken, address _newAllocation) public{
        isFinalized = _isInitialized;
        isInitialized = _isFinalized;
        if(_ICOType){
            ICO = ICOType.sale;
        }else{
            ICO = ICOType.preSale;
        }
        if(_restartVault){
            vault.close(wallets[uint8(Roles.beneficiary)]);
            vault = new RefundVault();
        }
        if(_ethWeiRaised != 1){
            ethWeiRaised = _ethWeiRaised;
        }
        if(_nonEthWeiRaised != 1){
            nonEthWeiRaised = _nonEthWeiRaised;
        }
        if(_newToken != 0x0){
            token = Token(_newToken);
        }
        if(_newAllocation != 0x0){
            lockedAllocation = SVTAllocation(_newAllocation);
        }
    }

    //При отправке eth если все условия выполнены отправит токены на адрес beneficiary
    function buyTokens(address beneficiary) public payable {
        require(beneficiary != 0x0);
        require(validPurchase());


        uint256 weiAmount = msg.value;

        uint256 ProfitProcent = getProfitPercent();
        // calculate token amount to be created
        uint256 tokens = weiAmount.mul(rate).mul(ProfitProcent).div(100000);


        // update state
        ethWeiRaised = ethWeiRaised.add(weiAmount);


        token.mint(beneficiary, tokens);
        TokenPurchase(msg.sender, beneficiary, weiAmount, tokens);

        forwardFunds();
    }

    //Метод по умолчанию. Если отправлен eth на алрес контракта и все условия соблюдены, отправитель получит токены.
    function () public payable {
        buyTokens(msg.sender);
    }
}

contract SVTAllocation{
    using SafeMath for uint256;

    Token public token;

	address owner;

    uint256 public unlockedAt;

    uint256 tokensCreated = 0;

    //Конструктор принимает адрес ERC20 монеты с которой будет этот контракт работать и владельца, которому пренадлежат средства.
    function SVTAllocation(Token _token, address _owner) public{
        unlockedAt = now + 12 * 30 /*days*/;
        token = _token;
        owner = _owner;
    }

    //если время заморозки истекло вернет средства владельцу.
    function unlock() public{
        require(now >= unlockedAt);
        require(token.transfer(owner,token.balanceOf(this)));
    }
}
