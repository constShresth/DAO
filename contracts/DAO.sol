// SPDX-License-Identifier: UNLICENSED
pragma solidity ^0.8.6;

import "@openzeppelin/contracts/access/AccessControl.sol";
//will be used to give access to roles to specified persons
import "@openzeppelin/contracts/security/ReentrancyGuard.sol";
//will be used to protect from reentrancy attack

contract DAO is ReentrancyGuard,AccessControl{
	bytes32 private immutable CONTRIBUTOR_ROLE=keccak256("CONTRIBUTOR");
	bytes32 private immutable STAKEHOLDER_ROLE=keccak256("STAKEHOLDER");
	//both this hash will help us to assign roles

	uint256 immutable MIN_STAKEHOLDER_CONTRIBUTION=1 ether;
	//minimum ether to be staked to become a stakeholder
	uint32 immutable MIN_VOTE_DURATION=3 minutes;

	uint32 totalProposals;
	uint256 public daoBalance;

	mapping(uint256=>ProposalStruct) private raisedProposals;
	//mapping proposal id(uint) to proposal struct; stores all the raised proposals
	mapping(address=>uint256[]) private stakeholderVotes;
	//mapping all the votes of an individual stakeholder to the different proposals
	mapping(uint256=>VotedStruct[]) private votedOn;
	//mapping voters address,timing & choice to proposal Id; voting information about a particular proposal
	mapping(address=>uint256) private contributors;
	mapping(address=>uint256) private stakeholders;
	//keeps track of all the contributors and stakeholders balance

	struct ProposalStruct{
		uint id;
		uint amount;
		uint duration;
		uint upvotes;
		uint downvotes;
		string title;//title for the proposal
		string description;
		bool passed;//proposal passed or failed
		bool paid;
		address payable beneficiary;//receipient if proposal is passed
		address proposar;
		address executor;
	}
	struct VotedStruct{
		address voter;//address of the voter
		uint timestamp;//what time did the voter vote
		bool chosen;//true means upvote & false means downvote
	}

	event Action(
		address indexed initiator,//address which is initiating the action
		bytes32 role,//contributor or stakeholder
		string message,
		address indexed beneficiary,
		uint amount
	);//take care of all the contributer & stakeholder's actions(general purpose event)

	modifier stakeholderOnly(string memory message){
		require(hasRole(STAKEHOLDER_ROLE,msg.sender),message);
		_;
	}
	modifier contributorOnly(string memory message){
		require(hasRole(CONTRIBUTOR_ROLE,msg.sender),message);
		_;
	}

	function createProposal(
		string memory title,
		string memory description,
		address beneficiary,
		uint amount
	)external stakeholderOnly("proposal creation allowed for the stakehlders only"){
		uint32 proposalId=totalProposals++;//1st time will be 0(since postincrement function is used)
		ProposalStruct storage proposal=raisedProposals[proposalId];
		proposal.id=proposalId;
		proposal.proposar=payable(msg.sender);
		proposal.title=title;
		proposal.description=description;
		proposal.beneficiary=payable(beneficiary);
		proposal.amount=amount;
		proposal.duration=block.timestamp+MIN_VOTE_DURATION;	

		emit Action(
			msg.sender,
			STAKEHOLDER_ROLE,
			"PROPOSAL RAISED",
			beneficiary,
			amount
		);
	}

	function handleVoting(ProposalStruct storage proposal) private{
		if(proposal.passed||block.timestamp>=proposal.duration){
			proposal.passed=true;
			revert("proposal duration expired");
		}
		uint256[] memory tempVotes=stakeholderVotes[msg.sender];
		for(uint256 i=0;i<tempVotes.length;i++){
			if(proposal.id==tempVotes[i]){
				revert("Double voting not allowed");
			}
		}
	}

	function Vote(
		uint256 proposalId,
		bool chosen
	)external stakeholderOnly("Unauthorized access: Stakeholders only permitted")returns(VotedStruct memory){
		ProposalStruct storage proposal=raisedProposals[proposalId];
		handleVoting(proposal);
		
		if(chosen) proposal.upvotes++;
		else proposal.downvotes++;

		stakeholderVotes[msg.sender].push(proposal.id);

		votedOn[proposal.id].push(VotedStruct(msg.sender,block.timestamp,chosen));

		emit Action(msg.sender, STAKEHOLDER_ROLE, "PROPOSAL VOTE", proposal.beneficiary, proposal.amount);

		return VotedStruct(msg.sender,block.timestamp,chosen);
	}

	function payTo(address to, uint amount)internal returns(bool){
		(bool success,)=payable(to).call{value:amount}("");
		require(success, "Payment Failed, something went wrong");
		return true;
	}

	function payBeneficiary(
		uint proposalId
	)public stakeholderOnly("Unauthorized: Stakeholder Only")nonReentrant() returns(uint256){

		ProposalStruct storage proposal=raisedProposals[proposalId];
		require(daoBalance>=proposal.amount,"Insufficient funds");
		if(proposal.paid) revert("Payment is already sent");
		if(proposal.upvotes<=proposal.downvotes) revert("Insufficient votes");

		proposal.paid=true;
		proposal.executor=msg.sender;
		daoBalance-=proposal.amount;

		payTo(proposal.beneficiary, proposal.amount);

		emit Action(msg.sender,STAKEHOLDER_ROLE,"PAYMENT TRANSFERRED",proposal.beneficiary,proposal.amount);
		return daoBalance;
	}

	function contribute() public payable{
		require(msg.value>0,"Contribution should be more than 0");
		if(!hasRole(STAKEHOLDER_ROLE, msg.sender)){
			//address is not stakeholder
			uint256 totalContribution=contributors[msg.sender]+msg.value;

			if(totalContribution>=MIN_STAKEHOLDER_CONTRIBUTION){
				stakeholders[msg.sender]=totalContribution;
				_grantRole(STAKEHOLDER_ROLE, msg.sender);
				//making the address stakeholder
			}
			contributors[msg.sender]+=msg.value;
			_grantRole(CONTRIBUTOR_ROLE, msg.sender);
			//making the address contributor
		}
		else{
			//address is stakeholder & all stakeholders are contributors
			contributors[msg.sender]+=msg.value;
			stakeholders[msg.sender]+=msg.value;
		}

		daoBalance+=msg.value;
		emit Action(msg.sender, CONTRIBUTOR_ROLE, "CONTRIBUTION RECEIVED", address(this), msg.value);
	}

	function getProposals() external view returns(ProposalStruct[] memory props){
		props=new ProposalStruct[](totalProposals);
		for (uint256 i = 0; i < totalProposals; i++) {
			props[i]=raisedProposals[i];
		}
		return props;
	}

	function getProposal(uint256 proposalId)public view returns(ProposalStruct memory){
		return raisedProposals[proposalId];
	}

	function getVotesOf(uint256 proposalId)public view returns(VotedStruct[] memory){
		return votedOn[proposalId];
	}

	function getStakeholderVotes()external view stakeholderOnly("Unauthorized: not a stakeholder")
	returns(uint256[] memory){
		return stakeholderVotes[msg.sender];
	}

	function getStakeholderBalance()external view stakeholderOnly("Unauthorized: not a stakeholder")
	returns(uint256){
		return stakeholders[msg.sender];
	}
///////////////////////////////////////////////////////////////////////////////////////////////

	function isStakeholder()external view returns (bool) {
        return stakeholders[msg.sender] > 0;
    }

	function getContributorBalance()
		external
		view
		contributorOnly("Denied: User is not a contributor")
		returns (uint256)
	{
		return contributors[msg.sender];
	}

	function isContributor()external view returns (bool) {
		return contributors[msg.sender] > 0;
	}

	function getBalance() external view returns (uint256) {
		return contributors[msg.sender];
	}


}