"use client";

import { ethers } from "ethers";
import { motion, AnimatePresence } from "framer-motion";
import {
  PlusIcon,
  WalletIcon,
  LogOutIcon,
  SearchIcon,
  ChevronLeftIcon,
  ChevronRightIcon,
} from "lucide-react";
import { useState, useEffect, useMemo } from "react";
import "react-datepicker/dist/react-datepicker.css";
import { AddAuctionModal } from "@/components/AddAuctionModal";
import { AuctionCardModal } from "@/components/AuctionCardModal";
import { Button } from "@/components/ui/button";
import { Input } from "@/components/ui/input";
import { auctionAddress, auctionAbi } from "@/constants";

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

declare global {
  interface Window {
    ethereum: any;
  }
}

export default function Home() {
  const [account, setAccount] = useState<string | null>(null);
  const [isHovering, setIsHovering] = useState(false);
  const [auctions, setAuctions] = useState<Auction[]>([]);
  const [searchTerm, setSearchTerm] = useState("");
  const [provider, setProvider] = useState<ethers.BrowserProvider | null>(null);
  const [contract, setContract] = useState<ethers.Contract | null>(null);
  const [isAddAuctionModalOpen, setIsAddAuctionModalOpen] = useState(false);
  const [currentPage, setCurrentPage] = useState(1);
  const [totalPages, setTotalPages] = useState(1);
  const pageSize = 10; // 每页显示的拍卖数量

  useEffect(() => {
    const web3Provider = new ethers.BrowserProvider(window.ethereum);
    setProvider(web3Provider);
    const auctionContract = new ethers.Contract(
      auctionAddress,
      auctionAbi,
      web3Provider
    );
    setContract(auctionContract);
  }, []);

  const connectWallet = async () => {
    if (typeof window.ethereum !== "undefined") {
      try {
        await window.ethereum.request({ method: "eth_requestAccounts" });
        const walletProvider = new ethers.BrowserProvider(
          window.ethereum,
          "any"
        );
        const signer = await walletProvider.getSigner();
        const address = await signer.getAddress();
        setAccount(address);
        setProvider(walletProvider);
        const walletContract = new ethers.Contract(
          auctionAddress,
          auctionAbi,
          signer
        );
        setContract(walletContract);
      } catch (error) {
        console.error("连接钱包失败:", error);
      }
    } else {
      alert("请安装 MetaMask!");
    }
  };

  const disconnectWallet = () => {
    setAccount(null);
    setIsHovering(false);
  };

  const fetchAuctions = async () => {
    if (contract) {
      try {
        const auctionData = await contract.getAuctionsByName(
          searchTerm,
          (currentPage - 1) * pageSize,
          pageSize
        );
        setAuctions(
          auctionData.map((auction: any) => ({
            auctionId: auction.auctionId,
            name: auction.name,
            startTime: Number(auction.startTime),
            endTime: Number(auction.endTime),
            initiator: auction.initiator,
            highestBidder: auction.highestBidder,
            highestBid: BigInt(auction.highestBid),
            beneficiary: auction.beneficiary,
            ended: auction.ended,
            ipfsHash: auction.ipfsHash,
          }))
        );
        const totalCount = await contract.getAuctionCountByName(searchTerm);
        setTotalPages(Math.ceil(Number(totalCount) / pageSize));
      } catch (error) {
        console.error("Failed to fetch auctions:", error);
        setAuctions([]);
        setTotalPages(1);
      }
    }
  };

  useEffect(() => {
    fetchAuctions();
  }, [contract, currentPage, searchTerm]);

  const filteredAuctions = useMemo(() => {
    return auctions.filter((auction) =>
      auction.name.toLowerCase().includes(searchTerm.toLowerCase())
    );
  }, [auctions, searchTerm]);

  const refreshAuctions = () => {
    fetchAuctions();
  };

  const openAddAuctionModal = () => {
    setIsAddAuctionModalOpen(true);
  };

  const closeAddAuctionModal = () => {
    setIsAddAuctionModalOpen(false);
  };

  const handlePreviousPage = () => {
    if (currentPage > 1) {
      setCurrentPage(currentPage - 1);
    }
  };

  const handleNextPage = () => {
    if (currentPage < totalPages) {
      setCurrentPage(currentPage + 1);
    }
  };

  return (
    <main className="min-h-screen bg-gradient-to-br from-purple-50 to-indigo-100 p-8">
      <div className="container mx-auto px-4 py-8">
        <motion.div
          initial={{ opacity: 0, y: -20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5 }}
          className="flex justify-between items-center mb-8 relative"
        >
          <div className="w-full">
            <h1 className="text-4xl font-bold text-center bg-clip-text text-transparent bg-gradient-to-r from-purple-600 to-indigo-600">
              Auction Dapp
            </h1>
          </div>
          <div className="absolute right-0">
            <AnimatePresence>
              {account ? (
                <motion.div
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.8 }}
                  transition={{ duration: 0.3 }}
                >
                  <Button
                    variant="outline"
                    className={`
                      flex items-center gap-2 
                      ${
                        isHovering
                          ? "bg-red-600 text-white hover:bg-red-700"
                          : "bg-white text-black hover:bg-gray-100"
                      }
                      transition-all duration-300
                    `}
                    onClick={disconnectWallet}
                    onMouseEnter={() => setIsHovering(true)}
                    onMouseLeave={() => setIsHovering(false)}
                  >
                    {isHovering ? (
                      <>
                        <LogOutIcon className="h-4 w-4" />
                        断开连接
                      </>
                    ) : (
                      <>
                        <WalletIcon className="h-4 w-4" />
                        {`${account.slice(0, 6)}...${account.slice(-4)}`}
                      </>
                    )}
                  </Button>
                </motion.div>
              ) : (
                <motion.div
                  initial={{ opacity: 0, scale: 0.8 }}
                  animate={{ opacity: 1, scale: 1 }}
                  exit={{ opacity: 0, scale: 0.8 }}
                  transition={{ duration: 0.3 }}
                >
                  <Button
                    variant="outline"
                    className="flex items-center gap-2 bg-gradient-to-r from-purple-500 to-indigo-500 text-white hover:from-purple-600 hover:to-indigo-600 transition-all duration-300"
                    onClick={connectWallet}
                  >
                    <WalletIcon className="h-4 w-4" />
                    连接钱包
                  </Button>
                </motion.div>
              )}
            </AnimatePresence>
          </div>
        </motion.div>

        <motion.div
          initial={{ opacity: 0, y: 20 }}
          animate={{ opacity: 1, y: 0 }}
          transition={{ duration: 0.5, delay: 0.2 }}
          className="flex flex-col md:flex-row justify-between items-center mb-8 space-y-4 md:space-y-0 md:space-x-4"
        >
          <div className="relative w-full md:w-auto">
            <Input
              placeholder="输入拍卖名称可搜索..."
              value={searchTerm}
              onChange={(e) => setSearchTerm(e.target.value)}
              className="pl-10 pr-4 py-2 w-full md:w-64 bg-white border-gray-300 rounded-md focus:ring-2 focus:ring-purple-500 focus:border-transparent"
            />
            <SearchIcon className="absolute left-3 top-1/2 transform -translate-y-1/2 text-gray-400" />
          </div>

          <Button
            className="flex items-center gap-2 bg-gradient-to-r from-purple-500 to-indigo-500 text-white hover:from-purple-600 hover:to-indigo-600 transition-all duration-300"
            onClick={openAddAuctionModal}
          >
            <PlusIcon className="h-4 w-4" />
            新的拍卖
          </Button>
        </motion.div>

        <motion.div
          initial={{ opacity: 0 }}
          animate={{ opacity: 1 }}
          transition={{ duration: 0.5, delay: 0.4 }}
          className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6"
        >
          <AnimatePresence>
            {filteredAuctions.map((auction, index) => (
              <motion.div
                key={auction.auctionId}
                initial={{ opacity: 0, scale: 0.9 }}
                animate={{ opacity: 1, scale: 1 }}
                exit={{ opacity: 0, scale: 0.9 }}
                transition={{ duration: 0.3, delay: index * 0.1 }}
              >
                <AuctionCardModal
                  auction={auction}
                  provider={provider}
                  account={account}
                  onAuctionUpdated={refreshAuctions}
                />
              </motion.div>
            ))}
          </AnimatePresence>
        </motion.div>

        <div className="flex justify-center mt-8 space-x-4">
          <Button
            onClick={handlePreviousPage}
            disabled={currentPage === 1}
            className="bg-purple-500 text-white hover:bg-purple-600"
          >
            <ChevronLeftIcon className="mr-2 h-4 w-4" />
            上一页
          </Button>
          <span className="text-purple-700 font-semibold">
            第 {currentPage} 页，共 {totalPages} 页
          </span>
          <Button
            onClick={handleNextPage}
            disabled={currentPage === totalPages}
            className="bg-purple-500 text-white hover:bg-purple-600"
          >
            下一页
            <ChevronRightIcon className="ml-2 h-4 w-4" />
          </Button>
        </div>

        <AddAuctionModal
          isOpen={isAddAuctionModalOpen}
          onClose={closeAddAuctionModal}
          provider={provider}
          account={account}
          onAuctionAdded={refreshAuctions}
        />
      </div>
    </main>
  );
}
