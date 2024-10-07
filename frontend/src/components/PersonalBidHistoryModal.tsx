import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
  DialogTrigger,
} from "@/components/ui/dialog";
import { auctionAddress, auctionAbi } from "@/constants";
import { ethers } from "ethers";
import { useState } from "react";

interface Bid {
  bidder: string;
  amount: bigint;
  bidTime: number;
}

export function PersonalBidHistoryModal({
  auctionId,
  account,
  provider,
}: {
  auctionId: number;
  account: string;
  provider: ethers.BrowserProvider | null;
}) {
  const [bids, setBids] = useState<Bid[]>([]);

  const fetchPersonalBidHistory = async () => {
    if (!provider || !account) return;

    const contract = new ethers.Contract(auctionAddress, auctionAbi, provider);
    const bidHistory = await contract.getBidsForAddress(auctionId, account);
    setBids(bidHistory);
  };

  return (
    <Dialog>
      <DialogTrigger asChild>
        <Button
          onClick={fetchPersonalBidHistory}
          variant="outline"
          className="flex-1"
        >
          查看我的竞价
        </Button>
      </DialogTrigger>
      <DialogContent className="sm:max-w-[600px]">
        <DialogHeader>
          <DialogTitle>我的竞价记录</DialogTitle>
        </DialogHeader>
        <div className="mt-4 max-h-[400px] overflow-y-auto">
          <table className="w-full">
            <thead>
              <tr>
                <th className="px-4 py-2 text-left">金额 (ETH)</th>
                <th className="px-4 py-2 text-left">时间</th>
              </tr>
            </thead>
            <tbody>
              {bids.map((bid, index) => (
                <tr key={index} className="border-t">
                  <td className="px-4 py-2">
                    {ethers.formatEther(bid.amount)}
                  </td>
                  <td className="px-4 py-2">
                    {new Date(Number(bid.bidTime) * 1000).toLocaleString()}
                  </td>
                </tr>
              ))}
            </tbody>
          </table>
        </div>
      </DialogContent>
    </Dialog>
  );
}
