"use client";

import { BidHistoryModal } from "./BidHistoryModal";
import { PersonalBidHistoryModal } from "./PersonalBidHistoryModal";
import { Button } from "@/components/ui/button";
import {
  Card,
  CardContent,
  CardFooter,
  CardHeader,
  CardTitle,
} from "@/components/ui/card";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { Input } from "@/components/ui/input";
import { auctionAddress, auctionAbi } from "@/constants";
import { ethers } from "ethers";
import { motion } from "framer-motion";
import { Clock, User, DollarSign, AlertCircle, Loader2 } from "lucide-react";
import { useState, useEffect } from "react";

interface Auction {
  auctionId: number;
  name: string;
  startTime: number;
  endTime: number;
  initiator: string;
  highestBidder: string;
  highestBid: bigint;
  beneficiary: string;
  ended: boolean;
  ipfsHash: string;
}

interface AuctionCardModalProps {
  auction: Auction;
  provider: ethers.BrowserProvider | null;
  account: string | null;
  onAuctionUpdated: () => void;
}

export function AuctionCardModal({
  auction,
  provider,
  account,
  onAuctionUpdated,
}: AuctionCardModalProps) {
  const [bidAmount, setBidAmount] = useState("");
  const [isPlacingBid, setIsPlacingBid] = useState(false);
  const [isEndingAuction, setIsEndingAuction] = useState(false);
  const [isWithdrawing, setIsWithdrawing] = useState(false);

  useEffect(() => {}, [auction, provider, onAuctionUpdated]);

  const placeBid = async () => {
    if (!provider || !account) {
      alert("Please connect your wallet first");
      return;
    }

    setIsPlacingBid(true);
    try {
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(auctionAddress, auctionAbi, signer);
      console.log("Placing bid for auction ID:", auction.auctionId);
      console.log("Bid amount:", bidAmount);

      // 计算实际需要发送的 ETH 数量
      const bidValue = ethers.parseEther(bidAmount);

      const tx = await contract.bid(auction.auctionId, {
        value: bidValue,
      });
      console.log("Transaction sent:", tx.hash);
      await tx.wait();
      console.log("Transaction confirmed");
      onAuctionUpdated();
    } catch (error: any) {
      console.error("Error placing bid:", error);
      if (error.reason) {
        alert(`Failed to place bid: ${error.reason}`);
      } else {
        alert("Failed to place bid. Please try again.");
      }
    } finally {
      setIsPlacingBid(false);
    }
  };

  const endAuction = async () => {
    if (!provider || !account) {
      alert("Please connect your wallet first");
      return;
    }

    setIsEndingAuction(true);
    try {
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(auctionAddress, auctionAbi, signer);
      const tx = await contract.endAuction(auction.auctionId);
      await tx.wait();
      onAuctionUpdated();
    } catch (error) {
      console.error("Error ending auction:", error);
      alert("Failed to end auction. Please try again.");
    } finally {
      setIsEndingAuction(false);
    }
  };

  const withdraw = async () => {
    if (!provider || !account) {
      alert("Please connect your wallet first");
      return;
    }

    setIsWithdrawing(true);
    try {
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(auctionAddress, auctionAbi, signer);
      const tx = await contract.withdraw(auction.auctionId);
      await tx.wait();
      onAuctionUpdated();
    } catch (error) {
      console.error("Error withdrawing:", error);
      alert("Failed to withdraw. Please try again.");
    } finally {
      setIsWithdrawing(false);
    }
  };

  return (
    <Card className="w-full max-w-md overflow-hidden bg-gradient-to-br from-purple-50 to-indigo-50 shadow-lg">
      <CardHeader className="bg-gradient-to-r from-purple-500 to-indigo-500 text-white">
        <CardTitle className="text-2xl font-bold">{auction.name}</CardTitle>
      </CardHeader>
      <CardContent className="p-6">
        <div className="relative aspect-video w-full overflow-hidden rounded-lg mb-6">
          <img
            src={`https://ipfs.io/ipfs/${auction.ipfsHash}`}
            alt={auction.name}
            className="w-full h-full object-cover transition-transform duration-300 hover:scale-105"
          />
        </div>
        <div className="space-y-4">
          <InfoItem
            icon={<Clock className="text-purple-500" />}
            label="开始日期"
          >
            {new Date(auction.startTime * 1000).toLocaleString()}
          </InfoItem>
          <InfoItem
            icon={<Clock className="text-indigo-500" />}
            label="结束日期"
          >
            {new Date(auction.endTime * 1000).toLocaleString()}
          </InfoItem>
          <InfoItem
            icon={<DollarSign className="text-green-500" />}
            label="当前最高出价"
          >
            <span className="text-lg font-bold text-green-600">
              {ethers.formatEther(auction.highestBid)} ETH
            </span>
          </InfoItem>
          <InfoItem
            icon={<AlertCircle className="text-red-500" />}
            label="状态"
          >
            {auction.ended ? "已结束" : "进行中"}
          </InfoItem>
        </div>
        {!auction.ended && (
          <motion.div
            initial={{ opacity: 0, y: 20 }}
            animate={{ opacity: 1, y: 0 }}
            transition={{ duration: 0.5 }}
            className="mt-6 space-y-4"
          >
            <Input
              type="number"
              placeholder="加价金额 (ETH)"
              value={bidAmount}
              onChange={(e) => setBidAmount(e.target.value)}
              className="w-full"
            />
            <Button
              onClick={placeBid}
              disabled={isPlacingBid}
              className="w-full bg-gradient-to-r from-purple-500 to-indigo-500 text-white hover:from-purple-600 hover:to-indigo-600 transition-all duration-300"
            >
              {isPlacingBid ? (
                <>
                  <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                  竞价中...
                </>
              ) : (
                "竞价"
              )}
            </Button>
          </motion.div>
        )}
        {!auction.ended && account === auction.initiator && (
          <Button
            onClick={endAuction}
            disabled={isEndingAuction}
            className="mt-2 w-full bg-red-500 text-white hover:bg-red-600"
          >
            {isEndingAuction ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                结束拍卖中...
              </>
            ) : (
              "结束拍卖"
            )}
          </Button>
        )}
        {auction.ended && (
          <Button
            onClick={withdraw}
            disabled={isWithdrawing}
            className="mt-2 w-full bg-green-500 text-white hover:bg-green-600"
          >
            {isWithdrawing ? (
              <>
                <Loader2 className="mr-2 h-4 w-4 animate-spin" />
                取款中...
              </>
            ) : (
              "取款"
            )}
          </Button>
        )}
      </CardContent>
      <CardFooter>
        <div className="flex space-x-2 w-full">
          <BidHistoryModal auctionId={auction.auctionId} provider={provider} />
          {account && (
            <PersonalBidHistoryModal
              auctionId={auction.auctionId}
              account={account}
              provider={provider}
            />
          )}
        </div>
      </CardFooter>
    </Card>
  );
}

function InfoItem({
  icon,
  label,
  children,
}: {
  icon: React.ReactNode;
  label: string;
  children: React.ReactNode;
}) {
  return (
    <div className="flex items-center space-x-2">
      {icon}
      <span className="text-sm font-medium text-gray-500">{label}:</span>
      <span className="text-sm text-gray-900">{children}</span>
    </div>
  );
}
