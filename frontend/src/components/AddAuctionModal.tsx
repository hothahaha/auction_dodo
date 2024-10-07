"use client";

import { Button } from "@/components/ui/button";
import {
  Dialog,
  DialogContent,
  DialogHeader,
  DialogTitle,
} from "@/components/ui/dialog";
import {
  Form,
  FormField,
  FormItem,
  FormLabel,
  FormControl,
  FormDescription,
  FormMessage,
} from "@/components/ui/form";
import { Input } from "@/components/ui/input";
import { Label } from "@/components/ui/label";
import { auctionAddress, auctionAbi } from "@/constants";
import axios, { AxiosProgressEvent } from "axios";
import { ethers } from "ethers";
import { motion, AnimatePresence } from "framer-motion";
import { Upload, Clock, X } from "lucide-react";
import { useState, useCallback } from "react";
import { useForm } from "react-hook-form";

// 使用环境变量存储 Pinata API 密钥
const PINATA_API_KEY = process.env.NEXT_PUBLIC_PINATA_API_KEY;
const PINATA_SECRET_API_KEY = process.env.NEXT_PUBLIC_PINATA_SECRET;

interface AddAuctionModalProps {
  isOpen: boolean;
  onClose: () => void;
  provider: ethers.BrowserProvider | null;
  account: string | null;
  onAuctionAdded: () => void;
}

export function AddAuctionModal({
  isOpen,
  onClose,
  provider,
  account,
  onAuctionAdded,
}: AddAuctionModalProps) {
  const [isUploading, setIsUploading] = useState(false);
  const [uploadProgress, setUploadProgress] = useState(0);
  const [previewImage, setPreviewImage] = useState<string | null>(null);
  const form = useForm({
    defaultValues: {
      name: "",
      image: null as File | null,
      days: 0,
      hours: 0,
      minutes: 0,
    },
  });

  const onSubmit = async (data: any) => {
    if (!provider || !account) {
      alert("请先连接钱包");
      return;
    }

    setIsUploading(true);
    try {
      // 上传图片到 Pinata
      const formData = new FormData();
      formData.append("file", data.image);

      const pinataResponse = await axios.post(
        "https://api.pinata.cloud/pinning/pinFileToIPFS",
        formData,
        {
          headers: {
            "Content-Type": "multipart/form-data",
            pinata_api_key: PINATA_API_KEY,
            pinata_secret_api_key: PINATA_SECRET_API_KEY,
          },
          onUploadProgress: (progressEvent: AxiosProgressEvent) => {
            const percentCompleted = Math.round(
              ((progressEvent.loaded ?? 0) * 100) / (progressEvent.total ?? 1)
            );
            setUploadProgress(percentCompleted);
          },
        }
      );

      const ipfsHash = pinataResponse.data.IpfsHash;

      // 计算拍卖持续时间（秒）
      const duration =
        data.days * 86400 + data.hours * 3600 + data.minutes * 60;

      // 调用合约创建拍卖
      const signer = await provider.getSigner();
      const contract = new ethers.Contract(auctionAddress, auctionAbi, signer);
      const tx = await contract.createAuction(
        data.name,
        duration,
        account,
        ipfsHash
      );
      await tx.wait();

      onAuctionAdded();
      onClose();
    } catch (error) {
      console.error("创建拍卖失败:", error);
      alert("创建拍卖失败，请重试");
    } finally {
      setIsUploading(false);
      setUploadProgress(0);
    }
  };

  const handleImageChange = useCallback(
    (e: React.ChangeEvent<HTMLInputElement>) => {
      const file = e.target.files?.[0];
      if (file) {
        const reader = new FileReader();
        reader.onloadend = () => {
          setPreviewImage(reader.result as string);
        };
        reader.readAsDataURL(file);
        form.setValue("image", file);
      }
    },
    [form]
  );

  const removeImage = useCallback(() => {
    setPreviewImage(null);
    form.setValue("image", null);
  }, [form]);

  return (
    <AnimatePresence>
      {isOpen && (
        <Dialog open={isOpen} onOpenChange={onClose}>
          <DialogContent className="sm:max-w-[425px] bg-gradient-to-br from-purple-50 to-indigo-50">
            <DialogHeader>
              <DialogTitle className="text-2xl font-bold text-center bg-clip-text text-transparent bg-gradient-to-r from-purple-600 to-indigo-600">
                添加新的拍卖品
              </DialogTitle>
            </DialogHeader>
            <motion.div
              initial={{ opacity: 0, y: 20 }}
              animate={{ opacity: 1, y: 0 }}
              exit={{ opacity: 0, y: -20 }}
              transition={{ duration: 0.3 }}
            >
              <Form {...form}>
                <form
                  onSubmit={form.handleSubmit(onSubmit)}
                  className="space-y-6"
                >
                  <FormField
                    control={form.control}
                    name="name"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel className="text-purple-700">
                          拍卖名称
                        </FormLabel>
                        <FormControl>
                          <Input
                            {...field}
                            placeholder="输入拍卖名称"
                            className="w-full border-purple-300 focus:border-purple-500 focus:ring-purple-500"
                          />
                        </FormControl>
                        <FormDescription className="text-indigo-600">
                          请输入一个独特的拍卖名称
                        </FormDescription>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                  <FormField
                    control={form.control}
                    name="image"
                    render={({ field }) => (
                      <FormItem>
                        <FormLabel className="text-purple-700">
                          拍卖品图片
                        </FormLabel>
                        <FormControl>
                          <div className="flex items-center justify-center w-full">
                            {previewImage ? (
                              <div className="relative w-full h-64">
                                <img
                                  src={previewImage}
                                  alt="Preview"
                                  className="w-full h-full object-cover rounded-lg"
                                />
                                <Button
                                  type="button"
                                  variant="destructive"
                                  size="icon"
                                  className="absolute top-2 right-2"
                                  onClick={removeImage}
                                >
                                  <X className="h-4 w-4" />
                                </Button>
                              </div>
                            ) : (
                              <Label
                                htmlFor="image-upload"
                                className="flex flex-col items-center justify-center w-full h-64 border-2 border-purple-300 border-dashed rounded-lg cursor-pointer bg-white hover:bg-purple-50 transition-colors duration-300"
                              >
                                <div className="flex flex-col items-center justify-center pt-5 pb-6">
                                  <Upload className="w-12 h-12 mb-4 text-purple-500" />
                                  <p className="mb-2 text-sm text-purple-700">
                                    <span className="font-semibold">
                                      点击上传
                                    </span>{" "}
                                    或拖拽文件至此处
                                  </p>
                                  <p className="text-xs text-indigo-600">
                                    PNG, JPG, GIF (最大 10MB)
                                  </p>
                                </div>
                                <Input
                                  id="image-upload"
                                  type="file"
                                  accept="image/*"
                                  className="hidden"
                                  onChange={handleImageChange}
                                />
                              </Label>
                            )}
                          </div>
                        </FormControl>
                        <FormMessage />
                      </FormItem>
                    )}
                  />
                  <div className="space-y-2">
                    <Label className="text-purple-700">拍卖持续时间</Label>
                    <div className="grid grid-cols-3 gap-4">
                      <FormField
                        control={form.control}
                        name="days"
                        render={({ field }) => (
                          <FormItem>
                            <FormControl>
                              <div className="relative">
                                <Input
                                  type="number"
                                  {...field}
                                  min="0"
                                  className="pr-12 border-purple-300 focus:border-purple-500 focus:ring-purple-500"
                                />
                                <span className="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 pointer-events-none">
                                  天
                                </span>
                              </div>
                            </FormControl>
                          </FormItem>
                        )}
                      />
                      <FormField
                        control={form.control}
                        name="hours"
                        render={({ field }) => (
                          <FormItem>
                            <FormControl>
                              <div className="relative">
                                <Input
                                  type="number"
                                  {...field}
                                  min="0"
                                  max="23"
                                  className="pr-12 border-purple-300 focus:border-purple-500 focus:ring-purple-500"
                                />
                                <span className="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 pointer-events-none">
                                  时
                                </span>
                              </div>
                            </FormControl>
                          </FormItem>
                        )}
                      />
                      <FormField
                        control={form.control}
                        name="minutes"
                        render={({ field }) => (
                          <FormItem>
                            <FormControl>
                              <div className="relative">
                                <Input
                                  type="number"
                                  {...field}
                                  min="0"
                                  max="59"
                                  className="pr-12 border-purple-300 focus:border-purple-500 focus:ring-purple-500"
                                />
                                <span className="absolute inset-y-0 right-0 flex items-center pr-3 text-gray-500 pointer-events-none">
                                  分
                                </span>
                              </div>
                            </FormControl>
                          </FormItem>
                        )}
                      />
                    </div>
                  </div>
                  <Button
                    type="submit"
                    disabled={isUploading}
                    className="w-full bg-gradient-to-r from-purple-500 to-indigo-500 text-white hover:from-purple-600 hover:to-indigo-600 transition-all duration-300"
                  >
                    {isUploading ? (
                      <div className="flex items-center justify-center">
                        <Clock className="mr-2 h-5 w-5 animate-spin" />
                        创建中... {Math.round(uploadProgress)}%
                      </div>
                    ) : (
                      "创建拍卖"
                    )}
                  </Button>
                </form>
              </Form>
            </motion.div>
          </DialogContent>
        </Dialog>
      )}
    </AnimatePresence>
  );
}
